# frozen_string_literal: true

require "optparse"
require "fileutils"
require "thuban"
require "porrima"
begin
  require "kochab"
rescue LoadError
end
begin
  require "spica"
rescue LoadError
end
begin
  require "zaniah"
rescue LoadError
end
require_relative "izar/version"

module Izar
  class Error < StandardError; end
  Change = Data.define(:path, :code, :index, :worktree) do
    def staged? = index != " " && index != "?"
    def untracked? = index == "?"
    def unstaged? = worktree != " "
  end

  class Repository
    attr_reader :repo

    def initialize(dir = Dir.pwd)
      @repo = Thuban::Repository.new(dir)
    rescue ArgumentError => error
      raise Error, error.message
    end

    def root = repo.root
    def branch = repo.branch || "(detached)"
    def head = repo.head

    def ahead_behind
      return {ahead: 0, behind: 0} unless repo.branch && head
      upstream = repo.resolve("refs/remotes/origin/#{repo.branch}")
      return {ahead: 0, behind: 0} unless upstream
      base = repo.merge_base(head, upstream)
      {ahead: count_until(head, base), behind: count_until(upstream, base)}
    rescue StandardError
      {ahead: 0, behind: 0}
    end

    def status
      repo.status.map { |entry| Change.new(path: entry.path, code: entry.code, index: entry.index, worktree: entry.worktree) }
    rescue StandardError => error
      raise Error, error.message
    end

    def grouped(filter: nil)
      changes = status
      if filter && !filter.empty?
        candidates = changes.map(&:path)
        matches = defined?(Spica) ? Spica.filter(filter, candidates).map(&:candidate) : candidates.select { |path| path.include?(filter) }
        changes = changes.select { |change| matches.include?(change.path) }
      end
      {
        staged: changes.select(&:staged?),
        unstaged: changes.select { |change| change.unstaged? && !change.untracked? },
        untracked: changes.select(&:untracked?)
      }
    end

    def stage(path)
      content = repo.worktree_content(path)
      if content
        stage_content(path, content)
      else
        index = repo.index
        index.remove(path)
        index.write
      end
      path
    rescue StandardError => error
      raise Error, error.message
    end

    def stage_content(path, content)
      index = repo.index
      entry = index[path]
      stat = File.stat(repo.worktree_path(path)) rescue nil
      mode = entry&.mode || (stat && (stat.mode & 0o100).positive? ? 0o100755 : 0o100644)
      index.stage(path, repo.write_blob(content), mode, stat: stat)
      index.write
      path
    end

    def unstage(path)
      index = repo.index
      head_content = repo.blob(path)
      if head_content
        entry = repo.tree.fetch(path)
        index.stage(path, entry.oid, entry.mode, stat: File.stat(repo.worktree_path(path)))
      else
        index.remove(path)
      end
      index.write
      path
    rescue StandardError => error
      raise Error, error.message
    end

    def discard(path, confirm: false)
      raise Error, "discard requires confirmation" unless confirm
      backup = repo.stash_push(message: "izar discard #{path}", include_untracked: true)
      repo.stash_pop if backup
      head_content = repo.blob(path)
      absolute = repo.worktree_path(path)
      if head_content
        FileUtils.mkdir_p(File.dirname(absolute))
        File.binwrite(absolute, head_content)
        entry = repo.tree.fetch(path)
        File.chmod(entry.mode & 0o777, absolute) unless entry.mode == 0o120000
        index = repo.index
        index.stage(path, entry.oid, entry.mode, stat: File.stat(absolute))
        index.write
      else
        File.unlink(absolute) if File.file?(absolute) || File.symlink?(absolute)
        index = repo.index
        index.remove(path)
        index.write
      end
      {path: path, backup: backup, message: backup ? "temporary stash #{backup} was restored before discarding #{path}" : "discarded #{path}"}
    rescue StandardError => error
      raise Error, error.message
    end

    def commit(message)
      message = message.to_s.strip
      raise Error, "commit message cannot be empty" if message.empty?
      raise Error, "nothing staged" unless status.any?(&:staged?)
      repo.commit!(message: message, author: repo.signature(role: :author), committer: repo.signature(role: :committer))
    rescue StandardError => error
      raise Error, error.message
    end

    def diff(path, context: 3) = Diff.new(self, path, context: context)

    private

    def count_until(reference, stop)
      repo.each_commit(reference, limit: 100_000).take_while { |commit| commit.oid != stop }.length
    end
  end

  class Diff
    attr_reader :repository, :path, :context

    def initialize(repository, path, context: 3)
      @repository, @path, @context = repository, path, context
    end

    def staged_to_worktree
      Porrima.diff(repository.repo.staged_blob(path).to_s, repository.repo.worktree_content(path).to_s, context: context).hunks
    end

    def head_to_staged
      Porrima.diff(repository.repo.blob(path).to_s, repository.repo.staged_blob(path).to_s, context: context).hunks
    end

    def stage_hunk(hunk)
      before = repository.repo.staged_blob(path).to_s
      after = Porrima.apply(before, hunk)
      repository.stage_content(path, after)
      after
    rescue StandardError => error
      raise Error, "cannot stage hunk: #{error.message}"
    end

    def unstage_hunk(hunk)
      before = repository.repo.staged_blob(path).to_s
      after = Porrima.revert(before, hunk)
      if after.empty? && repository.repo.blob(path).nil?
        index = repository.repo.index
        index.remove(path)
        index.write
      else
        repository.stage_content(path, after)
      end
      after
    rescue StandardError => error
      raise Error, "cannot unstage hunk: #{error.message}"
    end

    def lines
      staged_to_worktree.flat_map { |hunk| hunk.edits.map { |edit| [edit.kind, edit.text] } }
    end
  end

  class Model
    attr_reader :repository, :selected_path, :query

    def initialize(dir = Dir.pwd)
      @repository = Repository.new(dir)
      @selected_path = nil
      @query = ""
      reload
    end

    def reload
      @groups = repository.grouped(filter: query)
      paths = @groups.values.flatten.map(&:path)
      @selected_path = paths.include?(selected_path) ? selected_path : paths.first
      self
    end

    def groups = @groups
    def select(path) = (@selected_path = path)
    def filter(value)
      @query = value.to_s
      reload
    end
    def selected = groups.values.flatten.find { |change| change.path == selected_path }
  end

  module Config
    DEFAULTS = {"theme" => "dark", "split_ratio" => 0.35,
      "keymap" => {"stage" => "space", "commit" => "c"},
      "diff" => {"context" => 3, "highlight" => true}}.freeze
    module_function

    def load(path = File.join(Dir.pwd, ".izar.jsonc"))
      return DEFAULTS unless File.file?(path)
      value = Kochab.parse(File.read(path, encoding: "UTF-8")).value
      raise Error, "Izar config must be an object" unless value.is_a?(Hash)
      DEFAULTS.merge(value) { |_key, defaults, override| defaults.is_a?(Hash) && override.is_a?(Hash) ? defaults.merge(override) : override }
    rescue Kochab::ParseError => error
      raise Error, "invalid config: #{error.message}"
    end
  end

  module TUI
    module_function

    def keymap
      return nil unless defined?(Zaniah::Input::Keymap)
      Zaniah::Input::Keymap.new
        .bind("j", :next)
        .bind("k", :previous)
        .bind("space", :stage)
        .bind("s", :hunk)
        .bind("c", :commit)
        .bind("X", :discard)
        .bind("/", :filter)
        .bind("r", :reload)
        .bind("?", :help)
        .bind("q", :quit)
    end

    def run(model, input: $stdin, output: $stdout)
      unless input.tty? && output.tty? && defined?(Zaniah::Platform)
        View.render(model, out: output)
        return 0
      end
      window = Zaniah::Platform.open_window(backend: :tui, input: input, output: output, width: 120, height: 40)
      window.draw { Zaniah::Div.new.flex_col.p(16).child(Zaniah::Text.new(snapshot(model), size: 16)) }
      window.run
      0
    ensure
      window&.close
    end

    def snapshot(model)
      model.groups.map { |name, entries| "#{name}: #{entries.map(&:path).join(", ")}" }.join("\n")
    end
  end

  module View
    module_function

    def render(model, out: $stdout)
      out.puts "#{model.repository.branch} · #{model.groups.values.sum(&:length)} changes"
      {staged: "Staged", unstaged: "Unstaged", untracked: "Untracked"}.each do |key, title|
        entries = model.groups.fetch(key)
        out.puts "#{title} (#{entries.length})"
        entries.each { |change| out.puts "  #{change.code} #{change.path}" }
      end
      if model.selected_path
        out.puts "\nDiff: #{model.selected_path}"
        model.repository.diff(model.selected_path).lines.first(500).each { |kind, text| out.write(kind == :insert ? "+" : kind == :delete ? "-" : " "); out.write(text) }
      end
      out.puts "\n[space] stage  [s] hunk  [c] commit  [X] discard  [/] filter  [r] reload  [q] quit"
    end
  end

  class CLI
    def self.run(argv, out: $stdout, err: $stderr)
      options = {dir: Dir.pwd, filter: nil, action: :status, yes: false, tui: false}
      OptionParser.new do |opts|
        opts.banner = "Usage: izar [status|stage|unstage|discard|commit] [PATH]"
        opts.on("-C PATH") { |v| options[:dir] = v }
        opts.on("--filter TEXT") { |v| options[:filter] = v }
        opts.on("--yes") { options[:yes] = true }
        opts.on("--tui") { options[:tui] = true }
        opts.on("-m MESSAGE") { |v| options[:message] = v }
      end.parse!(argv)
      options[:action] = argv.shift&.to_sym || :status
      repository = Repository.new(options[:dir])
      case options[:action]
      when :status
        model = Model.new(options[:dir]).filter(options[:filter]) if options[:filter]
        model ||= Model.new(options[:dir])
        options[:tui] ? TUI.run(model, output: out) : View.render(model, out: out)
      when :stage then repository.stage(argv.fetch(0)); out.puts "staged #{argv.fetch(0)}"
      when :unstage then repository.unstage(argv.fetch(0)); out.puts "unstaged #{argv.fetch(0)}"
      when :discard then out.puts repository.discard(argv.fetch(0), confirm: options[:yes]).fetch(:message)
      when :commit then out.puts "committed #{repository.commit(options[:message] || argv.fetch(0))}"
      else raise Error, "unknown command: #{options[:action]}"
      end
      0
    rescue OptionParser::ParseError, KeyError, Error => error
      err.puts "izar: #{error.message}"
      1
    end
  end
end

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
  require "zaniah/ui"
rescue LoadError
end
require_relative "izar/version"

module Izar
  class Error < StandardError; end

  class Operation
    attr_reader :error

    def initialize(&block)
      @status = :running
      @thread = Thread.new do
        block.call
      rescue StandardError => error
        @error = error
      ensure
        @status = :done
      end
    end

    def running? = @status == :running
    def done? = @status == :done
  end

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
        stat = File.stat(repo.worktree_path(path)) rescue nil
        index.stage(path, entry.oid, entry.mode, stat: stat)
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

    def stage_all
      status.each { |change| stage(change.path) unless change.staged? && !change.unstaged? }
      self
    end

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

    def lines(limit: 50_000)
      staged_to_worktree.flat_map { |hunk| hunk.edits.map { |edit| [edit.kind, edit.text] } }.first(limit)
    end

    def highlight(lines: nil, limit: 50_000)
      source = Array(lines || repository.repo.worktree_content(path).to_s.lines).map do |line|
        line.to_s.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
      end
      require "antares"
      require "rouge"
      lexer = Rouge::Lexer.guess(filename: path)
      highlighter = Antares::Highlighter.new(lexer: lexer, lines: ->(index) { source[index] }, line_count: -> { source.length })
      highlighter.tokens_in(0...[source.length, limit].min)
    rescue LoadError, StandardError
      source.to_a.first(limit).map { |line| [[nil, line]] }
    end
  end

  class Model
    attr_reader :repository, :selected_path, :query, :config, :message, :operation

    def initialize(dir = Dir.pwd, config: Config.load(File.join(dir, ".izar.jsonc")))
      @repository = Repository.new(dir)
      @config = config
      @selected_path = nil
      @query = ""
      @message = nil
      @operation = nil
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

    def paths = groups.values.flatten.map(&:path)

    def move(delta)
      return nil if paths.empty?
      index = [paths.index(selected_path).to_i + delta, 0].max
      select(paths[[index, paths.length - 1].min])
    end

    def diff
      return nil unless selected_path
      context = config.dig("diff", "context").to_i
      repository.diff(selected_path, context: context.positive? ? context : 3)
    end

    def stage_selected(async: false)
      return reload unless selected_path
      perform(async) { repository.stage(selected_path); reload }
    end

    def unstage_selected(async: false)
      return reload unless selected_path
      perform(async) { repository.unstage(selected_path); reload }
    end

    def toggle_selected(async: false)
      return reload unless selected
      selected.staged? && !selected.unstaged? ? unstage_selected(async: async) : stage_selected(async: async)
    end

    def stage_selected_hunk(async: false)
      change = selected
      return reload unless change
      perform(async) do
        if change.staged? && !change.unstaged?
          hunks = repository.diff(change.path).head_to_staged
          repository.diff(change.path).unstage_hunk(hunks.first) if hunks.first
        else
          hunks = repository.diff(change.path).staged_to_worktree
          repository.diff(change.path).stage_hunk(hunks.first) if hunks.first
        end
        reload
      end
    end

    def stage_all(async: false)
      perform(async) { repository.stage_all; reload }
    end

    def discard_selected(async: false)
      return reload unless selected_path
      perform(async) { repository.discard(selected_path, confirm: true); reload }
    end

    def commit(message, async: false)
      perform(async) { repository.commit(message); reload }
    end

    def busy?
      operation&.running? || false
    end

    def poll_operation
      return false unless operation&.done?
      @message = operation.error.message if operation.error
      @operation = nil
      true
    end

    def message=(value)
      @message = value
    end

    private

    def perform(async)
      return yield unless async
      return false if busy?
      @operation = Operation.new { yield }
      true
    end
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
      config = DEFAULTS.merge(value) do |_key, defaults, override|
        defaults.is_a?(Hash) && override.is_a?(Hash) ? defaults.merge(override) : override
      end
      validate(config)
      config
    rescue Kochab::ParseError => error
      raise Error, "invalid config: #{error.message}"
    end

    def validate(config)
      unknown = config.keys.map(&:to_s) - DEFAULTS.keys
      raise Error, "unknown config key: #{unknown.first}" unless unknown.empty?
      raise Error, "theme must be a string" unless config["theme"].is_a?(String)
      ratio = config["split_ratio"]
      raise Error, "split_ratio must be between 0 and 1" unless ratio.is_a?(Numeric) && ratio.finite? && ratio.between?(0, 1)
      keymap = config["keymap"]
      raise Error, "keymap must be an object" unless keymap.is_a?(Hash)
      %w[stage commit].each do |key|
        value = keymap[key]
        raise Error, "keymap.#{key} must be a non-empty string" unless value.is_a?(String) && !value.empty?
      end
      unknown_keymap = keymap.keys.map(&:to_s) - DEFAULTS["keymap"].keys
      raise Error, "unknown keymap key: #{unknown_keymap.first}" unless unknown_keymap.empty?
      diff = config["diff"]
      raise Error, "diff must be an object" unless diff.is_a?(Hash)
      context = diff["context"]
      raise Error, "diff.context must be a non-negative integer" unless context.is_a?(Integer) && context >= 0
      raise Error, "diff.highlight must be boolean" unless diff["highlight"] == true || diff["highlight"] == false
      unknown_diff = diff.keys.map(&:to_s) - DEFAULTS["diff"].keys
      raise Error, "unknown diff key: #{unknown_diff.first}" unless unknown_diff.empty?
      config
    end
  end

  module TUI
    module_function

    def keymap(config = Config::DEFAULTS)
      return nil unless defined?(Zaniah::Input::Keymap)
      bindings = config.fetch("keymap", {})
      Zaniah::Input::Keymap.new
        .bind("j", :next)
        .bind("k", :previous)
        .bind(bindings.fetch("stage", "space"), :stage)
        .bind("a", :stage_all)
        .bind("s", :hunk)
        .bind(bindings.fetch("commit", "c"), :commit)
        .bind("X", :discard)
        .bind("/", :filter)
        .bind("r", :reload)
        .bind("?", :help)
        .bind("q", :quit)
    end

    class Session
      attr_reader :model, :message

      def initialize(model, async: false)
        @model = model
        @async = async
        @keymap = TUI.keymap(model.config)
        @fallback = {"j" => :next, "k" => :previous,
          model.config.dig("keymap", "stage").to_s => :stage,
          "a" => :stage_all, "s" => :hunk, "X" => :discard,
          model.config.dig("keymap", "commit").to_s => :commit,
          "/" => :filter, "r" => :reload, "?" => :help, "q" => :quit}
        @fallback[" "] ||= :stage
        @message = nil
      end

      def dispatch(key, commit_message: nil, confirm: false, filter_text: nil)
        action = @keymap&.dispatch(key) || @fallback[key]
        case action
        when :next then model.move(1)
        when :previous then model.move(-1)
        when :stage then model.toggle_selected(async: @async)
        when :stage_all then model.stage_all(async: @async)
        when :hunk then model.stage_selected_hunk(async: @async)
        when :discard
          confirm ? model.discard_selected(async: @async) : (@message = "discard cancelled")
        when :filter
          model.filter(filter_text.to_s)
        when :commit
          begin
            model.commit(commit_message, async: @async)
          rescue Error => error
            @message = error.message
          end
        when :reload then model.reload
        when :help then @message = "j/k move · space stage · a all · s hunk · X discard · c commit · q quit"
        when :quit then return :quit
        end
        model.message = @message
        action
      rescue Error => error
        @message = error.message
        model.message = @message
        :error
      end
    end

    def run(model, input: $stdin, output: $stdout)
      unless input.tty? && output.tty? && defined?(Zaniah::Platform)
        View.render(model, out: output)
        return 0
      end
      require "io/console"
      session = Session.new(model)
      input.raw do
        loop do
          output.write("\e[2J\e[H")
          View.render(model, out: output)
          key = input.getch
          if key == "c"
            output.write("commit message: ")
            message = input.cooked { input.gets.to_s.chomp }
            result = session.dispatch(key, commit_message: message)
          elsif key == "X"
            output.write("discard #{model.selected_path}? [y/N] ")
            confirm = input.cooked { input.getch.to_s.downcase == "y" }
            result = session.dispatch(key, confirm: confirm)
          elsif key == "/"
            output.write("filter: ")
            query = input.cooked { input.gets.to_s.chomp }
            result = session.dispatch(key, filter_text: query)
          else
            result = session.dispatch(key)
          end
          break if result == :quit
        end
      end
      0
    end

    def snapshot(model)
      model.groups.map { |name, entries| "#{name}: #{entries.map(&:path).join(", ")}" }.join("\n")
    end
  end

  module View
    module_function

    def element(model)
      theme = defined?(Zaniah::Theme) ? Zaniah::Theme.dark : nil
      return Zaniah::UI::EmptyState.new("No changes", message: "Working tree is clean") unless theme

      sidebar = Zaniah::UI::Sidebar.new(width: 280)
      model.groups.each do |name, entries|
        sidebar.child(Zaniah::UI::Label.new("#{name.to_s.capitalize} (#{entries.length})", tone: :muted, size: :xs))
        entries.each do |change|
          variant = change.path == model.selected_path ? :secondary : :ghost
          sidebar.child(Zaniah::UI::Button.new("#{change.code} #{change.path}", size: :sm, variant: variant).w_full
            .on_click { |_event, context| model.select(change.path); context.window.request_frame })
        end
      end

      main = Zaniah::Div.new.flex_col.gap(12).p(24).bg(theme.colors.background)
      status_children = [Zaniah::UI::Label.new("#{model.repository.branch} · #{model.groups.values.sum(&:length)} changes", size: :sm)]
      status_children << Zaniah::UI::Spinner.new(size: 14) if model.busy?
      status_children << Zaniah::UI::Spacer.new
      status_children << Zaniah::UI::Label.new(model.message.to_s, tone: :muted, size: :xs)
      main.child(Zaniah::UI::StatusBar.new(*status_children))
      if model.selected_path && model.diff
        lines = model.diff.lines(limit: 50_000)
        main.child(Zaniah::UI::Label.new("Diff: #{model.selected_path}", size: :lg))
        main.child(Zaniah::List.new(count: lines.length, estimated_height: 20) do |index|
          kind, text = lines[index]
          Zaniah::Div.new.h(20).child(Zaniah::UI::RichText.new(diff_runs(model, kind, text, theme), selectable: false))
        end.h(680))
      else
        main.child(Zaniah::UI::EmptyState.new("Select a change", message: "Choose a file from the sidebar"))
      end
      Zaniah::UI::SplitPane.new(sidebar, main, ratio: model.config.fetch("split_ratio", 0.35))
    end

    def render(model, out: $stdout)
      ahead = model.repository.ahead_behind
      out.puts "#{model.repository.branch} ↑#{ahead[:ahead]} ↓#{ahead[:behind]} · #{model.groups.values.sum(&:length)} changes"
      {staged: "Staged", unstaged: "Unstaged", untracked: "Untracked"}.each do |key, title|
        entries = model.groups.fetch(key)
        out.puts "#{title} (#{entries.length})"
        entries.each { |change| out.puts "  #{change.code} #{change.path}" }
      end
      if model.selected_path
        out.puts "\nDiff: #{model.selected_path}"
        model.diff.lines.first(500).each { |kind, text| out.write(kind == :insert ? "+" : kind == :delete ? "-" : " "); out.write(text) }
      end
      out.puts "\n#{model.message}" if model.respond_to?(:message) && model.message
      out.puts "\n[space] stage  [a] all  [s] hunk  [c] commit  [X] discard  [/] filter  [r] reload  [q] quit"
    end

    def diff_runs(model, kind, text, theme)
      prefix = kind == :insert ? "+" : kind == :delete ? "-" : " "
      plain = "#{prefix}#{text}".encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
      return [{text: plain, color: diff_color(kind, theme)}] unless model.config.dig("diff", "highlight")

      tokens = model.diff.highlight(lines: [text], limit: 1).first || [[nil, text]]
      [{text: prefix, color: diff_color(kind, theme)}] + tokens.map do |token, value|
        {text: value.to_s.encode(Encoding::UTF_8, invalid: :replace, undef: :replace), color: token_color(token, kind, theme)}
      end
    rescue StandardError
      [{text: "#{prefix}#{text}".encode(Encoding::UTF_8, invalid: :replace, undef: :replace), color: diff_color(kind, theme)}]
    end

    def diff_color(kind, theme)
      case kind
      when :insert then theme.colors.success
      when :delete then theme.colors.danger
      else theme.colors.text
      end
    end

    def token_color(token, kind, theme)
      return diff_color(kind, theme) unless token.respond_to?(:shortname)
      case token.shortname.to_s
      when /k|c/ then theme.colors.text_muted
      when /nb|nc|nf|n/ then theme.colors.accent
      when /s|dl/ then theme.colors.success
      when /m|mi|mf/ then theme.colors.warning
      else theme.colors.text
      end
    end
  end

  module GUI
    module_function

    def run(model, output: $stdout)
      raise Error, "GUI backend unavailable" unless defined?(Zaniah::Platform)
      backend = RUBY_PLATFORM.include?("darwin") ? :mac : RUBY_PLATFORM.match?(/mswin|mingw/) ? :windows : :linux
      window = Zaniah::Platform.open_window(backend: backend, width: 1200, height: 800, title: "Izar")
      session = TUI::Session.new(model, async: true)
      window.draw { View.element(model) }
      window.on_tick do
        window.request_frame if model.busy?
        window.request_frame if model.poll_operation
      end
      window.on_input do |event|
        next unless event.is_a?(Zaniah::Input::KeyDown)
        key = event.keystroke
        next if %w[c X].include?(key)
        result = session.dispatch(key)
        window.request_frame unless result == :quit
        window.close if result == :quit
      end
      window.run
    rescue StandardError => error
      output.puts "izar: GUI backend unavailable; using TUI (#{error.message})"
      TUI.run(model, input: $stdin, output: output)
    ensure
      window&.close
    end
  end

  class CLI
    def self.run(argv, out: $stdout, err: $stderr, input: $stdin)
      options = {dir: Dir.pwd, filter: nil, action: :status, yes: false, tui: false, gui: false}
      OptionParser.new do |opts|
        opts.banner = "Usage: izar [status|stage|unstage|discard|commit] [PATH]"
        opts.on("-C PATH") { |v| options[:dir] = v }
        opts.on("--filter TEXT") { |v| options[:filter] = v }
        opts.on("--yes") { options[:yes] = true }
        opts.on("--tui") { options[:tui] = true }
        opts.on("--gui") { options[:gui] = true }
        opts.on("-m MESSAGE") { |v| options[:message] = v }
      end.parse!(argv)
      options[:action] = argv.shift&.to_sym || :status
      repository = Repository.new(options[:dir])
      case options[:action]
      when :status
        model = Model.new(options[:dir]).filter(options[:filter]) if options[:filter]
        model ||= Model.new(options[:dir])
        if options[:gui] && input.tty? && out.tty?
          GUI.run(model, output: out)
        else
          out.puts "izar: GUI backend unavailable; using TUI" if options[:gui]
          options[:tui] ? TUI.run(model, input: input, output: out) : View.render(model, out: out)
        end
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

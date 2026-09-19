# frozen_string_literal: true

require "tempfile"
require "fileutils"

RSpec.describe Izar do
  def repository
    dir = Dir.mktmpdir("izar")
    system("git", "init", "-q", "-b", "main", dir)
    File.write(File.join(dir, "README.md"), "one\ntwo\n")
    system("git", "-C", dir, "add", "README.md")
    system("git", "-C", dir, "-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "-qm", "initial")
    [Izar::Repository.new(dir), dir]
  end

  it "stages files and applies a single hunk" do
    repo, dir = repository
    File.write(File.join(dir, "README.md"), "one\nthree\n")
    hunk = repo.diff("README.md").staged_to_worktree.fetch(0)
    repo.diff("README.md").stage_hunk(hunk)
    expect(repo.status.map(&:code)).to eq(["M "])
    expect(repo.repo.staged_blob("README.md")).to eq("one\nthree\n")
  ensure
    FileUtils.remove_entry(dir) if dir
  end

  it "rejects empty commits and protects discard behind confirmation" do
    repo, dir = repository
    expect { repo.commit(" ") }.to raise_error(Izar::Error, /empty/)
    File.write(File.join(dir, "README.md"), "changed\n")
    expect { repo.discard("README.md") }.to raise_error(Izar::Error, /confirmation/)
    result = repo.discard("README.md", confirm: true)
    expect(result[:message]).to include("README.md")
    expect(File.read(File.join(dir, "README.md"))).to eq("one\ntwo\n")
  ensure
    FileUtils.remove_entry(dir) if dir
  end

  it "unstages a deletion without requiring a worktree stat" do
    repo, dir = repository
    File.unlink(File.join(dir, "README.md"))
    repo.stage("README.md")
    repo.unstage("README.md")
    expect(repo.status.map(&:code)).to eq([" D"])
  ensure
    FileUtils.remove_entry(dir) if dir
  end

  it "dispatches TUI stage actions through the model" do
    repo, dir = repository
    File.write(File.join(dir, "README.md"), "changed\n")
    model = Izar::Model.new(dir)
    expect(Izar::TUI::Session.new(model).dispatch(" ")).to eq(:stage)
    expect(repo.status.map(&:code)).to eq(["M "])
  ensure
    FileUtils.remove_entry(dir) if dir
  end

  it "filters through the interactive session and exposes messages to the view" do
    repo, dir = repository
    File.write(File.join(dir, "notes.txt"), "notes\n")
    model = Izar::Model.new(dir)
    session = Izar::TUI::Session.new(model)
    expect(session.dispatch("/", filter_text: "notes")).to eq(:filter)
    expect(model.paths).to eq(["notes.txt"])
    session.dispatch("?")
    expect(model.message).to include("j/k move")
  ensure
    FileUtils.remove_entry(dir) if dir
  end

  it "honors configured stage and commit keys" do
    repo, dir = repository
    File.write(File.join(dir, "README.md"), "changed\n")
    model = Izar::Model.new(dir, config: Izar::Config::DEFAULTS.merge("keymap" => {"stage" => "t", "commit" => "m"}))
    session = Izar::TUI::Session.new(model)
    expect(session.dispatch("t")).to eq(:stage)
    expect(repo.status.map(&:code)).to eq(["M "])
  ensure
    FileUtils.remove_entry(dir) if dir
  end

  it "rejects malformed configuration before key dispatch" do
    path = Tempfile.new(["izar", ".jsonc"])
    path.write('{"keymap":{"stage":42}}')
    path.close
    expect { Izar::Config.load(path.path) }.to raise_error(Izar::Error, /keymap.stage/)
  ensure
    path&.unlink
  end
end

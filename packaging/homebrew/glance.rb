# Canonical copy of the Homebrew formula. The live copy lives in the tap
# repo at akira-toriyama/homebrew-tap as Formula/glance.rb. Keep this in
# sync and bump `url`/`sha256` on every release tag (see
# packaging/homebrew/README.md).
class Glance < Formula
  desc "macOS CLI: display stdin in a non-activating NSPanel popover"
  homepage "https://github.com/akira-toriyama/glance"
  url "https://github.com/akira-toriyama/glance/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  license "MIT"
  head "https://github.com/akira-toriyama/glance.git", branch: "main"

  depends_on macos: :ventura

  def install
    system "./build.sh"
    bin.install "bin/glance"
  end

  def caveats
    <<~EOS
      glance is a one-shot CLI. Pipe text in to show a non-activating
      NSPanel popover that does NOT steal keyboard focus from the source
      app. Intended as the "result view" end of selection-driven
      pipelines (eventfx → wand → action shell → glance).

      Quick smoke test:
        printf 'Hello' | glance --title 'Greeting'

      Documentation: #{homepage}
    EOS
  end

  test do
    assert_path_exists bin/"glance"
    assert_match(/glance/, shell_output("#{bin}/glance --version"))
  end
end

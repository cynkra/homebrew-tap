class CynkraBaseline < Formula
  desc "Read-only security baseline check for Macs used for cynkra work"
  homepage "https://github.com/cynkra/homebrew-tap"
  url "https://github.com/cynkra/homebrew-tap/archive/refs/tags/v0.2.12.tar.gz"
  sha256 "36d10ad51128d8d8aac62865d9c018a3f9acab208e12a9d0d52793b64524073c"
  license "MIT"

  depends_on :macos
  depends_on "osv-scanner"
  depends_on "syft"

  def install
    bin.install "src/macos-baseline-check.sh" => "cynkra-baseline"
  end

  service do
    run [opt_bin/"cynkra-baseline", "run"]
    environment_variables PATH: std_service_path_env
    run_at_load true
    interval 86400
    log_path var/"log/cynkra-baseline.log"
    error_log_path var/"log/cynkra-baseline.log"
  end

  def caveats
    <<~EOS
      Set up once, with your cynkra address:
        cynkra-baseline owner name@cynkra.com
        brew services start cynkra-baseline
      Show the result now: cynkra-baseline check
    EOS
  end

  test do
    assert_match "Usage", shell_output("#{bin}/cynkra-baseline owner invalid 2>&1", 2)
  end
end

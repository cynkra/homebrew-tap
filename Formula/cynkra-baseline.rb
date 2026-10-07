class CynkraBaseline < Formula
  desc "Read-only security baseline check for Macs used for cynkra work"
  homepage "https://github.com/cynkra/homebrew-tap"
  url "https://github.com/cynkra/homebrew-tap/archive/refs/tags/v0.2.6.tar.gz"
  sha256 "517510f3ab4300fba7da12db14ca7273e65d61451a355b7dd896235c750eb2e6"
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

  test do
    assert_match "Usage", shell_output("#{bin}/cynkra-baseline owner invalid 2>&1", 2)
  end
end

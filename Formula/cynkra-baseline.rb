class CynkraBaseline < Formula
  desc "Read-only security baseline check for Macs used for cynkra work"
  homepage "https://github.com/cynkra/homebrew-tap"
  url "https://github.com/cynkra/homebrew-tap/archive/refs/tags/v0.2.1.tar.gz"
  sha256 "391f7749f45e102d7dd99b2ebace7f2d0afa8b105670bfbb100219f62eff87d7"
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

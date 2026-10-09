class CynkraEndpointCheck < Formula
  desc "Read-only security check of Macs used for cynkra work"
  homepage "https://github.com/cynkra/homebrew-tap"
  url "https://github.com/cynkra/homebrew-tap/archive/refs/tags/v0.3.5.tar.gz"
  sha256 "393c4ed35548e1f9790367bf20c5ad5e7876508fa95a73cbe2546a04ca6916fb"
  license "MIT"

  depends_on :macos
  depends_on "osv-scanner"
  depends_on "syft"

  def install
    bin.install "src/cynkra-endpoint-check.sh" => "cynkra-endpoint-check"
  end

  service do
    run [opt_bin/"cynkra-endpoint-check", "run"]
    environment_variables PATH: std_service_path_env
    run_at_load true
    interval 86400
    log_path var/"log/cynkra-endpoint-check.log"
    error_log_path var/"log/cynkra-endpoint-check.log"
  end

  def caveats
    <<~EOS
      Set up once, with your cynkra address:
        cynkra-endpoint-check owner name@cynkra.com
        brew services start cynkra-endpoint-check
      Show the result now: cynkra-endpoint-check check
    EOS
  end

  test do
    assert_match "Usage", shell_output("#{bin}/cynkra-endpoint-check owner invalid 2>&1", 2)
  end
end

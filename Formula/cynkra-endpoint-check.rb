class CynkraEndpointCheck < Formula
  desc "Read-only security check of Macs used for cynkra work"
  homepage "https://github.com/cynkra/homebrew-tap"
  url "https://github.com/cynkra/homebrew-tap/archive/refs/tags/v0.3.4.tar.gz"
  sha256 "d89984bb937ee4ccba3b23db1d2272d38b1c17ad362e36b2acfd5745d10075b9"
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

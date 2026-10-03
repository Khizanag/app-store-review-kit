class Asrk < Formula
  desc "Check an Apple app against the App Review Guidelines before you submit"
  homepage "https://github.com/Khizanag/app-store-review-kit"
  url "https://github.com/Khizanag/app-store-review-kit/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "7735bab06aca69932b723e2e9821cdd44079173a62ce3db3024ce5b272473046"
  license "MIT"

  depends_on xcode: ["26.0", :build]
  depends_on :macos

  def install
    system "swift", "build", "--disable-sandbox", "-c", "release", "--product", "asrk"
    bin.install ".build/release/asrk"
  end

  test do
    assert_match "rules, guidelines", shell_output("#{bin}/asrk version")
    (testpath/"App/Main.swift").write "let url = URL(string: \"http://localhost:8080\")"
    output = shell_output("#{bin}/asrk check #{testpath} --fail-on never")
    assert_match "build.debug-endpoints", output
  end
end

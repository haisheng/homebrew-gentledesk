class Gentledesk < Formula
  desc "Local desktop companion for GentleDesk Chrome extension"
  homepage "https://github.com/haisheng/homebrew-gentledesk"
  url "https://github.com/haisheng/homebrew-gentledesk/releases/download/v1.3.0/gentledesk-source-1.3.0.tar.gz"
  sha256 "7caf73f12e9031f65a3eca19e97e7800aceaa4a6939603b04a5337a357ce28aa"
  version "1.3.0"
  depends_on :macos

  def install
    system "/usr/bin/xcrun", "swiftc", "-O", "-module-cache-path", buildpath/"ModuleCache", "Host.swift", "-o", "deskassit-native"
    system "/usr/bin/codesign", "--force", "--sign", "-", "deskassit-native"
    libexec.install "deskassit-native", "install.sh", "uninstall.sh", "gentledesk", "VERSION"
    bin.write_exec_script libexec/"gentledesk"
  end

  def caveats
    <<~EOS
      Connect Chrome: gentledesk setup YOUR_CHROME_EXTENSION_ID
      Refresh registration after each upgrade. No desktop files are uploaded.
      Remove registration: gentledesk uninstall
    EOS
  end

  test do
    system libexec/"deskassit-native", "--self-test"
    system bin/"gentledesk", "setup", "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "--test-root", testpath/"isolated"
    assert_path_exists testpath/"isolated/NativeMessagingHosts/com.deskassit.desktop.json"
  end
end

class Ak < Formula
  desc "ADB extensions kit - Essential ADB utilities for Android development"
  homepage "https://github.com/luminousvault/adb-extensions"
  url "https://github.com/luminousvault/adb-extensions/releases/download/v1.2.0/adb-extensions-v1.2.0.tar.gz"
  sha256 "27110f57848dcd11f15c24288363ed78437e16d9a5f692c80c906e235c2da1e6"
  license "MIT"
  version "1.2.0"

  # depends_on "android-platform-tools"  # adb 의존성

  def install
    # 쉘 스크립트 설치
    bin.install "build/ak" => "ak"
    # Completion 설치
    zsh_completion.install "build/completions/_ak"
  end
  
  def caveats
    <<~EOS
        ⚠️ IMPORTANT: To enable tab completion, restart your terminal
    EOS
  end

  test do
    # 버전 체크
    assert_match "1.0.3", shell_output("#{bin}/ak --version")
    
    # 도움말 체크
    assert_match "ADB extensions kit", shell_output("#{bin}/ak --version")
    
    # install 커맨드 체크
    assert_match "install", shell_output("#{bin}/ak --help")
  end
end

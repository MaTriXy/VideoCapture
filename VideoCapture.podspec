Pod::Spec.new do |s|
  s.name = "VideoCapture"
  s.version = "1.0.0"

  s.summary = "A lightweight object that outputs camera stream"
  s.homepage = "https://github.com/eugenebokhan/VideoCapture"

  s.author = {
    "Eugene Bokhan" => "eugenebokhan@protonmail.com"
  }

  s.ios.deployment_target = "12.3"

  s.source = {
    :git => "https://github.com/eugenebokhan/VideoCapture.git",
    :tag => "#{s.version}"
  }
  s.source_files = "Sources/**/*.{swift,metal}"

  s.swift_version = "5.1"
end

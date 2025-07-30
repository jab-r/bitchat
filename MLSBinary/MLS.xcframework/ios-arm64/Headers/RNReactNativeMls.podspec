require "json"

package = JSON.parse(File.read(File.join(__dir__, "..", "package.json")))

Pod::Spec.new do |s|
  s.name         = "RNReactNativeMls"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = package["homepage"]
  s.license      = package["license"]
  s.authors      = { package["author"] => "" }

  s.platforms    = { :ios => "11.0" }
  # Use local source instead of git
  s.source       = { :path => "." }

  # Include both RNReactNativeMls and MLSModule
  s.source_files = "**/*.{h,m,mm,swift}"
  
  # Include prebuilt Rust library
  s.vendored_libraries = "libs/*.a"
  s.library = "react_native_mls_rust"
  
  # Simple configuration - just ensure we can find React headers
  s.pod_target_xcconfig = {
    'HEADER_SEARCH_PATHS' => '$(PODS_ROOT)/Headers/Public/React-Core',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++'
  }
  
  # Only depend on React-Core
  s.dependency "React-Core"
end
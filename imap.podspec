#
# Be sure to run `pod lint imap.podspec' to ensure this is a
# valid spec.
#
# Remove all comments before submitting the spec.
#
Pod::Spec.new do |s|
  s.name     = 'imap'
  s.version  = '0.0.1'
  s.license  = 'MIT'
  s.summary  = 'A short description of imap.'
  s.homepage = 'http://EXAMPLE/imap'
  s.author   = { 'bcoe' => 'bencoe@gmail.com' }

  # Specify the location from where the source should be retreived.
  #
  s.source   = { :git => 'git://github.com/bcoe/IMAPClient.git', :tag => '0.0.1' }

  s.description = 'An asynchrounous IMAP client for iOS.'

  # If this Pod runs only on iOS or OS X, then specify that with one of
  # these, or none if it runs on both platforms.
  #
  s.platform = :ios

  # A list of file patterns which select the source files that should be
  # added to the Pods project. If the pattern is a directory then the
  # path will automatically have '*.{h,m,mm,c,cpp}' appended.
  #
  # Alternatively, you can use the FileList class for even more control
  # over the selected files.
  # (See http://rake.rubyforge.org/classes/Rake/FileList.html.)
  #
  s.source_files = 'Classes', 'Classes/**/*.{h,m}'
end

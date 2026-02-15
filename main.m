Run # Компилируем в исполняемый файл с добавлением фреймворка UniformTypeIdentifiers
main.m:166:23: error: use of undeclared identifier 'AVAssetImageGeneratorResultSucceeded'; did you mean 'AVAssetImageGeneratorSucceeded'?
  166 |         if (result == AVAssetImageGeneratorResultSucceeded && image) {
      |                       ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
      |                       AVAssetImageGeneratorSucceeded
/Applications/Xcode_16.4.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS18.5.sdk/System/Library/Frameworks/AVFoundation.framework/Headers/AVAssetImageGenerator.h:81:2: note: 'AVAssetImageGeneratorSucceeded' declared here
   81 |         AVAssetImageGeneratorSucceeded = 0,
      |         ^
main.m:473:39: warning: 'kUTTypeMovie' is deprecated: first deprecated in iOS 15.0 - Use UTTypeMovie or UTType.movie (swift) instead. [-Wdeprecated-declarations]
  473 |     picker.mediaTypes = @[(NSString *)kUTTypeMovie];
      |                                       ^
/Applications/Xcode_16.4.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS18.5.sdk/System/Library/Frameworks/CoreServices.framework/Headers/UTCoreTypes.h:880:26: note: 'kUTTypeMovie' has been explicitly marked deprecated here
  880 | extern const CFStringRef kUTTypeMovie                                API_DEPRECATED("Use UTTypeMovie or UTType.movie (swift) instead.", ios(3.0, 15.0), macos(10.4, 12.0), tvos(9.0, 15.0), watchos(1.0, 8.0));
      |                          ^
1 warning and 1 error generated.
Error: Process completed with exit code 1.

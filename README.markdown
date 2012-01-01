IMAPClient
==========

An asynchrounous IMAP client for iOS.

Usage
-----

```objective-c
IMAP* imap = [[IMAP alloc] init];
[imap connect: @"imap.gmail.com" port: 993 callback: ^(bool connected, NSError *error){
	[imap login: @"fakeuser@gmail.com" password: @"fakepass" callback: ^(NSString* response){
		[imap select: @"[Gmail]/All Mail" callback: ^(NSString* response){
			[imap fetch: @"200" fields: @"(body[header.fields (from to subject date)])" callback: ^(NSString* message){
				NSLog(@"%@", message);
			}];
		}];
	}];
}];
```
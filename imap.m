//
//  imap.m
//  IMAP
//
//  Created by Benjamin Coe on 11-12-22.
//  Copyright 2011 Attachments.me. All rights reserved.
//

#import "imap.h"

@implementation IMAP

- (IMAP*) init {
	self = [super init];
	[self initializeVariables];
	return self;
}

- (IMAP*) initWithUseUID: (bool) useUID {
	self = [super init];
	[self initializeVariables];
	_useUID = useUID;
	return self;
}

- (void)initializeVariables {
	_useUID = FALSE;
	_commandCount = 0;
	_readSize = 1024;
	_parsingBlock = NULL;
	_inputStreamReady = FALSE;
	_outputStreamReady = FALSE;
	_response = [NSMutableString new];
	_uidCommands = [[NSArray alloc] initWithObjects: 
		@"FETCH",
		@"SEARCH",
		nil
	];
}

- (void)open {
	CFReadStreamRef readStream = NULL;
	CFWriteStreamRef writeStream = NULL;
	CFStreamCreatePairWithSocketToHost(kCFAllocatorDefault, (CFStringRef)host, port, &readStream, &writeStream);
	if (readStream && writeStream) {
		CFReadStreamSetProperty(readStream, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanTrue);
		CFWriteStreamSetProperty(writeStream, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanTrue);

		_inputStream = (NSInputStream *)readStream;
		[_inputStream retain];
		[_inputStream setDelegate:self];
		[_inputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
		[_inputStream open];

		_outputStream = (NSOutputStream *)writeStream;
		[_outputStream retain];
		[_outputStream setDelegate:self];
		[_outputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
		[_outputStream open];
		
		if (port == 993) {
			[_inputStream setProperty:NSStreamSocketSecurityLevelNegotiatedSSL 
									   forKey:NSStreamSocketSecurityLevelKey];
			[_outputStream setProperty:NSStreamSocketSecurityLevelNegotiatedSSL 
										 forKey:NSStreamSocketSecurityLevelKey];  
			
			NSDictionary *settings = [[NSDictionary alloc] initWithObjectsAndKeys:
									  [NSNumber numberWithBool:YES], kCFStreamSSLAllowsExpiredCertificates,
									  [NSNumber numberWithBool:YES], kCFStreamSSLAllowsAnyRoot,
									  [NSNumber numberWithBool:NO], kCFStreamSSLValidatesCertificateChain,
									  kCFNull,kCFStreamSSLPeerName,
									  nil];
			
			CFReadStreamSetProperty((CFReadStreamRef)_inputStream, kCFStreamPropertySSLSettings, (CFTypeRef)settings);
			CFWriteStreamSetProperty((CFWriteStreamRef)_outputStream, kCFStreamPropertySSLSettings, (CFTypeRef)settings);
			[settings release];
		}
	}
}

// Both streams call this when events happen
- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode {
	if (aStream == _inputStream) {
		[self handleInputStreamEvent:eventCode];
	} else if (aStream == _outputStream) {
		[self handleOutputStreamEvent:eventCode];
	}
}

- (void)handleInputStreamEvent:(NSStreamEvent)eventCode {
	switch (eventCode) {
		case NSStreamEventHasBytesAvailable:
			[self readBytes];
			break;
		case NSStreamEventOpenCompleted:
			if (!_inputStreamReady) {
				_inputStreamReady = TRUE;
				if (_outputStreamReady && _inputStreamReady) {
					[self connected];
				}
			}
		default:
		case NSStreamEventErrorOccurred:
			break;
	}
}

- (void)handleOutputStreamEvent:(NSStreamEvent)eventCode; {
	switch (eventCode) {
		case NSStreamEventHasBytesAvailable:
			[self readBytes];
			break;
		case NSStreamEventHasSpaceAvailable:
		{
			if (!_outputStreamReady) {
				_outputStreamReady = TRUE;
				if (_outputStreamReady && _inputStreamReady) {
					[self connected];
				}
			}
		}
		case NSStreamEventOpenCompleted:
			break;
		default:
		case NSStreamEventErrorOccurred:
			break;
	}
}

- (void)readBytes {
	unsigned char buf[_readSize + 1];
	memset(buf, 0, sizeof(char) * (_readSize + 1) );
	[_inputStream read:buf maxLength:_readSize];
	NSString* data = [NSString stringWithUTF8String:(char *)buf];
	[_response appendString:data];
	if (_parsingBlock) {
		_parsingBlock();
	}
}

- (void)connect: (NSString*) h port: (int) p callback: (void(^)(bool))handler {
	host = h;
	port = p;
	_connectedCallback = [handler copy];
	[self open];
}

- (void)connected {
	_connectedCallback(TRUE);
    [_connectedCallback release];
}

- (void)login: (NSString*) username password: (NSString*) password callback: (void(^)(bool)) handler {
	NSString *command = [NSString stringWithFormat: @"LOGIN %@ %@", username, password];
	[_response setString: @""];
	void (^_handler)(bool connected) = [handler copy];

	[self setParsingBlock: ^{
		if([_response rangeOfString:@"\r\n" options:NSCaseInsensitiveSearch].location != NSNotFound) {
			_handler(TRUE);
			[_handler release];
		}
	}];
	
	[self runCommand: command commandName: @"LOGIN"];
}

- (void)select: (NSString*) mailbox callback: (void(^)(bool)) handler {
	NSString *command = [NSString stringWithFormat: @"SELECT \"%@\"", mailbox];
	[_response setString: @""];
	void (^_handler)(bool connected) = [handler copy];
	[self setParsingBlock: ^{
		if([_response rangeOfString:@"\r\n" options:NSCaseInsensitiveSearch].location != NSNotFound) {
			_handler(TRUE);
			[_handler release];
		}
	}];
	
	[self runCommand: command commandName: @"SELECT"];
}

- (void)fetch: (NSString*) ids fields: (NSString*) fields callback: (void(^)(NSString*)) handler {
	NSString *command = [NSString stringWithFormat: @"FETCH %@ %@", ids, fields];
	
	[_response setString: @""];
	void (^_handler)(NSString* message) = [handler copy];
	
	[self setParsingBlock: ^{
		if([_response rangeOfString:@"\r\n" options:NSCaseInsensitiveSearch].location != NSNotFound) {
			_handler(_response);
			[_handler release];
		}
	}];
	
	[self runCommand: command commandName: @"FETCH"];
}

- (void)search: (NSString*) query callback: (void(^)(NSString*)) handler {
	NSString *command = [NSString stringWithFormat: @"SEARCH %@", query];
	
	[_response setString: @""];
	void (^_handler)(NSString* message) = [handler copy];
	
	[self setParsingBlock: ^{
		if([_response rangeOfString:@"\r\n" options:NSCaseInsensitiveSearch].location != NSNotFound) {
			_handler(_response);
			[_handler release];
		}
	}];
	
	[self runCommand: command commandName: @"SEARCH"];
}

- (void)setParsingBlock: (void(^)()) block {
	if (_parsingBlock) {
		[_parsingBlock release];
	}
	_parsingBlock = [block copy];
}

- (void)runCommand: (NSString*) command commandName: (NSString*) commandName {
	_commandCount++;
	NSString *str = @"";
	if (_useUID && [_uidCommands containsObject: commandName]) {
		str = [NSString stringWithFormat: @"a%i UID %@\r\n", _commandCount, command];
	} else {
		str = [NSString stringWithFormat: @"a%i %@\r\n", _commandCount, command];
	}
	NSData *strData = [str dataUsingEncoding:NSASCIIStringEncoding];
	[_outputStream write:[strData bytes] maxLength:[strData length]];
}

-(void)dealloc {
	[_response release];
	if (_parsingBlock) {
		[_parsingBlock release];
	}
	[_inputStream release];
	[_outputStream release];
	[_uidCommands release];
	[super dealloc];
}

@end

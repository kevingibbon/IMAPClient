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
		@"UIDCOMMAND",
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
		case NSStreamEventHasBytesAvailable: {
			[self readBytes];
			break;
		}
		case NSStreamEventOpenCompleted: {
			if (!_inputStreamReady) {
				_inputStreamReady = TRUE;
				if (_outputStreamReady && _inputStreamReady) {
					_connectedCallback(TRUE, NULL);
					[_connectedCallback release];
				}
			}
			break;
		}
		case NSStreamEventErrorOccurred: {
			NSError *error = [_inputStream streamError];
			_connectedCallback(FALSE, error);
			[_connectedCallback release];
			break;
		}
		default:
			break;
	}
}

- (void)handleOutputStreamEvent:(NSStreamEvent)eventCode; {
	switch (eventCode) {
		case NSStreamEventHasBytesAvailable: {
			break;
		}
		case NSStreamEventHasSpaceAvailable: {
			{
				if (!_outputStreamReady) {
					_outputStreamReady = TRUE;
					if (_outputStreamReady && _inputStreamReady) {
						_connectedCallback(TRUE, NULL);
						[_connectedCallback release];
					}
				}
			}
			break;
		}
		case NSStreamEventOpenCompleted: {
			break;
		}
		case NSStreamEventErrorOccurred: {
			NSError *error = [_outputStream streamError];
			_connectedCallback(FALSE, error);
			[_connectedCallback release];
			break;
		}
		default:
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

- (void)connect: (NSString*) h port: (int) p callback: (void(^)(bool, NSError*))handler {
	host = h;
	port = p;
	_connectedCallback = [handler copy];
	[self open];
}

- (void)login: (NSString*) username password: (NSString*) password callback: (void(^)(NSString*)) handler {
	NSString *command = [NSString stringWithFormat: @"LOGIN %@ %@", username, password];
	[self command: command commandName: @"LOGIN" callback: handler];
}

- (void)select: (NSString*) mailbox callback: (void(^)(NSString*)) handler {
	NSString *command = [NSString stringWithFormat: @"SELECT \"%@\"", mailbox];
	[self command: command commandName: @"SELECT" callback: handler];
}

- (void)fetch: (NSString*) ids fields: (NSString*) fields callback: (void(^)(NSString*)) handler {
	NSString *command = [NSString stringWithFormat: @"FETCH %@ %@", ids, fields];
	[self command: command commandName: @"FETCH" callback: handler];
}

- (void)search: (NSString*) query callback: (void(^)(NSString*)) handler {
	NSString *command = [NSString stringWithFormat: @"SEARCH %@", query];
	[self command: command commandName: @"SEARCH" callback: handler];
}

- (void)command: (NSString*) command callback: (void(^)(NSString*)) handler {
	[self command: command commandName: @"COMMAND" callback: handler];
}

- (void)uid: (NSString*) command callback: (void(^)(NSString*)) handler {
	[self command: command commandName: @"UIDCOMMAND" callback: handler];
}

- (void)command: (NSString*) command commandName: (NSString*)commandName callback: (void(^)(NSString*)) handler {
	[_response setString: @""];
	
	void (^_handler)(NSString* message) = [handler copy];
	
	[self setParsingBlock: ^{
		if([_response rangeOfString:@"\r\n" options:NSCaseInsensitiveSearch].location != NSNotFound) {
			_handler([NSString stringWithFormat: @"%@", _response]);
			[_handler release];
		}
	}];
	
	[self runCommand: command commandName: commandName];
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
	if (_parsingBlock) {
		[_parsingBlock release];
	}
	[_response release];
	[_inputStream release];
	[_outputStream release];
	[_uidCommands release];
	[super dealloc];
}

@end

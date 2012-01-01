//
//  imap.h
//  IMAP
//
//  Created by Benjamin Coe on 11-12-22.
//  Copyright 2011 Attachments.me. All rights reserved.
//

@interface IMAP : NSObject <NSStreamDelegate> {
	NSString *host;
	int port;
	
	NSMutableString *_response;
	int _commandCount;
	unsigned int _readSize;	
	bool _outputStreamReady;
	bool _inputStreamReady;
	bool _useUID;
	
	void (^_connectedCallback)(bool, NSError*);
	void (^_parsingBlock)();
	NSInputStream *_inputStream;
	NSOutputStream *_outputStream;
	NSArray *_uidCommands;
	
}

- (IMAP*) initWithUseUID: (bool)useUID;
- (void)initializeVariables;
- (void)stream:(NSStream*)aStream handleEvent:(NSStreamEvent)eventCode;
- (void)handleInputStreamEvent:(NSStreamEvent)eventCode;
- (void)handleOutputStreamEvent:(NSStreamEvent)eventCode;
- (void)readBytes;
- (void)open;
- (void)setParsingBlock: (void(^)()) block;
- (void)runCommand: (NSString*) command commandName: (NSString*) commandName;
- (void)command: (NSString*) command commandName: (NSString*)commandName callback: (void(^)(NSString*)) handler;

- (void)connect: (NSString*) h port: (int) p callback: (void(^)(bool, NSError*))handler;
- (void)login: (NSString*) username password: (NSString*) password callback: (void(^)(NSString*)) handler;
- (void)select: (NSString*) mailbox callback: (void(^)(NSString*)) handler;
- (void)fetch: (NSString*) ids fields: (NSString*) fields callback: (void(^)(NSString*)) handler;
- (void)search: (NSString*) query callback: (void(^)(NSString*)) handler;
- (void)command: (NSString*) command callback: (void(^)(NSString*)) handler;
- (void)uid: (NSString*) command callback: (void(^)(NSString*)) handler;

@end

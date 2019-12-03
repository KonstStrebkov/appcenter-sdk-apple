// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSHttpIngestionPrivate.h"
#import "MSTestFrameworks.h"
#import "MSHttpClient.h"
#import "MSIngestionDelegate.h"
#import "MSTestUtil.h"
#import "MSDevice.h"
#import "MSHttpTestUtil.h"

@interface MSHttpIngestionTests : XCTestCase

@property(nonatomic) MSHttpIngestion *sut;
@property(nonatomic) MSHttpClient *httpClientMock;

@end

@implementation MSHttpIngestionTests

- (void)setUp {
  [super setUp];

  NSDictionary *queryStrings = @{@"api-version" : @"1.0.0"};
  self.httpClientMock = OCMPartialMock([MSHttpClient new]);

  // sut: System under test
  self.sut = [[MSHttpIngestion alloc] initWithHttpClient:self.httpClientMock
                                                 baseUrl:@"https://www.contoso.com"
                                                      apiPath:@"/test-path"
                                                      headers:nil
                                                 queryStrings:queryStrings
                                               retryIntervals:@[ @(0.5), @(1), @(1.5) ]];
}

- (void)tearDown {
  [super tearDown];

  self.sut = nil;
}

- (void)testValidETagFromResponse {

  // If
  NSString *expectedETag = @"IAmAnETag";
  NSHTTPURLResponse *response = [NSHTTPURLResponse new];
  id responseMock = OCMPartialMock(response);
  OCMStub([responseMock allHeaderFields]).andReturn(@{@"Etag" : expectedETag});

  // When
  NSString *eTag = [MSHttpIngestion eTagFromResponse:responseMock];

  // Then
  XCTAssertEqualObjects(expectedETag, eTag);
}

- (void)testInvalidETagFromResponse {

  // If
  NSHTTPURLResponse *response = [NSHTTPURLResponse new];
  id responseMock = OCMPartialMock(response);
  OCMStub([responseMock allHeaderFields]).andReturn(@{@"Etag1" : @"IAmAnETag"});

  // When
  NSString *eTag = [MSHttpIngestion eTagFromResponse:responseMock];

  // Then
  XCTAssertNil(eTag);
}

- (void)testNoETagFromResponse {

  // If
  NSHTTPURLResponse *response = [NSHTTPURLResponse new];

  // When
  NSString *eTag = [MSHttpIngestion eTagFromResponse:response];

  // Then
  XCTAssertNil(eTag);
}

- (void)testNullifiedDelegate {

  // If
  @autoreleasepool {
    __weak id delegateMock = OCMProtocolMock(@protocol(MSIngestionDelegate));
    [self.sut addDelegate:delegateMock];

    // When
    delegateMock = nil;
  }

  // Then
  // There is a bug somehow in NSHashTable where the count on the table itself is not decremented while an object is deallocated and auto
  // removed from the table. The NSHashtable allObjects: is used instead to remediate.
  assertThatUnsignedLong(self.sut.delegates.allObjects.count, equalToInt(0));
}

- (void)testCallDelegatesOnPaused {

  // If
  id delegateMock1 = OCMProtocolMock(@protocol(MSIngestionDelegate));
  id delegateMock2 = OCMProtocolMock(@protocol(MSIngestionDelegate));
  [self.sut resume];
  [self.sut addDelegate:delegateMock1];
  [self.sut addDelegate:delegateMock2];

  // When
  [self.sut pause];

  // Then
  OCMVerify([delegateMock1 ingestionDidPause:self.sut]);
  OCMVerify([delegateMock2 ingestionDidPause:self.sut]);
}

// TODO: Move this to base MSHttpIngestion test.
- (void)testCallDelegatesOnResumed {

  // If
  id delegateMock1 = OCMProtocolMock(@protocol(MSIngestionDelegate));
  id delegateMock2 = OCMProtocolMock(@protocol(MSIngestionDelegate));
  [self.sut pause];
  [self.sut addDelegate:delegateMock1];
  [self.sut addDelegate:delegateMock2];

  // When
  [self.sut pause];
  [self.sut resume];

  // Then
  OCMVerify([delegateMock1 ingestionDidResume:self.sut]);
  OCMVerify([delegateMock2 ingestionDidResume:self.sut]);
}

- (void)testSetBaseURL {

  // If
  NSString *path = @"path";
  NSURL *expectedURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", @"https://www.contoso.com/", path]];
  self.sut.apiPath = path;

  // Query should be the same.
  NSString *query = self.sut.sendURL.query;

  // When
  [self.sut setBaseURL:(NSString * _Nonnull)[expectedURL.URLByDeletingLastPathComponent absoluteString]];

  // Then
  assertThat([self.sut.sendURL absoluteString], is([NSString stringWithFormat:@"%@?%@", expectedURL.absoluteString, query]));
}

- (void)testSetInvalidBaseURL {

  // If
  NSURL *expected = self.sut.sendURL;
  NSString *invalidURL = @"\notGood";

  // When
  [self.sut setBaseURL:invalidURL];

  // Then
  assertThat(self.sut.sendURL, is(expected));
}

- (void)testCompressHTTPBodyWhenNeeded {
  id deviceMock = OCMPartialMock([MSDevice new]);
  OCMStub([deviceMock isValid]).andReturn(YES);
  MSLogContainer *container = [MSTestUtil createLogContainerWithId:@"1" device:deviceMock];

  // Respond with a retryable error.
  [MSHttpTestUtil stubHttp500Response];

  // Send the call.
  [self.sut sendAsync:(NSObject *)container eTag:nil authToken:nil completionHandler:^(NSString * _Nonnull callId __unused, NSHTTPURLResponse * _Nullable response __unused, NSData * _Nullable data __unused, NSError * _Nullable error __unused) {
  }];

  // Ensure that HTTP is called with compression.
  OCMVerify([self.httpClientMock sendAsync:OCMOCK_ANY method:OCMOCK_ANY headers:OCMOCK_ANY data:OCMOCK_ANY retryIntervals:OCMOCK_ANY compressionEnabled:YES completionHandler:OCMOCK_ANY]);
}

- (void)testPausedWhenAllRetriesUsed {
  
  // If
  XCTestExpectation *responseReceivedExpectation = [self expectationWithDescription:@"Used all retries."];
  id deviceMock = OCMPartialMock([MSDevice new]);
  OCMStub([deviceMock isValid]).andReturn(YES);
  MSLogContainer *container = [MSTestUtil createLogContainerWithId:@"1" device:deviceMock];
  
  // Respond with a retryable error.
  [MSHttpTestUtil stubHttp500Response];
  
  // Send the call.
  [self.sut sendAsync:(NSObject *)container eTag:nil authToken:nil completionHandler:^(NSString * _Nonnull callId __unused, NSHTTPURLResponse * _Nullable response __unused, NSData * _Nullable data __unused, NSError * _Nullable error __unused) {
    [responseReceivedExpectation fulfill];
  }];
  [self waitForExpectationsWithTimeout:10
                               handler:^(NSError *error) {
                                 XCTAssertTrue(self.sut.paused);
                                 if (error) {
                                   XCTFail(@"Expectation Failed with error: %@", error);
                                 }
                               }];
}

@end

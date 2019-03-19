#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol MSSerializableDocument

@required
/**
 * Create a dictionary from the object.
 *
 * @return Dictionary representing the object.
 */
- (NSDictionary *)serializeToDictionary;

/**
 * Construct an object from a dictionary.
 *
 * @param dictionary of object
 *
 * @return An instance of the object
 */
- (instancetype)initFromDictionary:(NSDictionary *)dictionary;

@end

NS_ASSUME_NONNULL_END

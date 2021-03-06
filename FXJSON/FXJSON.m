//
//  FXJSON.m
//
//  Version 1.1
//
//  Created by Nick Lockwood on 27/10/2009.
//  Copyright 2009 Charcoal Design
//
//  Distributed under the permissive zlib License
//  Get the latest version from here:
//
//  https://github.com/nicklockwood/FXJSON
//
//  This software is provided 'as-is', without any express or implied
//  warranty.  In no event will the authors be held liable for any damages
//  arising from the use of this software.
//
//  Permission is granted to anyone to use this software for any purpose,
//  including commercial applications, and to alter it and redistribute it
//  freely, subject to the following restrictions:
//
//  1. The origin of this software must not be misrepresented; you must not
//  claim that you wrote the original software. If you use this software
//  in a product, an acknowledgment in the product documentation would be
//  appreciated but is not required.
//
//  2. Altered source versions must be plainly marked as such, and must not be
//  misrepresented as being the original software.
//
//  3. This notice may not be removed or altered from any source distribution.
//

#import "FXJSON.h"


@interface FXJSON ()

id FXparseObject(char *buffer, NSInteger *start, NSInteger length, id<FXJSONDelegate> delegate);
id FXparseDictionary(char *buffer, NSInteger *index, NSInteger length, id<FXJSONDelegate> delegate);
id FXparseArray(char *buffer, NSInteger *index, NSInteger length, id<FXJSONDelegate> delegate);
id FXparseString(char *buffer, NSInteger *index, NSInteger length);
id FXparseNumber(char *buffer, NSInteger *index, NSInteger length);
id FXparseTrue(char *buffer, NSInteger *index, NSInteger length);
id FXparseFalse(char *buffer, NSInteger *index, NSInteger length);
id FXparseNull(char *buffer, NSInteger *index, NSInteger length);
void FXstripNulls(id object);

@end


@implementation FXJSON

static inline BOOL FXisWhiteSpace(char character)
{
    switch (character)
    {
        case ' ':
        case '\f':
        case '\n':
        case '\r':
        case '\t':
        {
            return YES;
        }
        default:
        {
            return NO;
        }
    }
}

static inline BOOL FXisNumeric(char character)
{
    switch (character)
    {
        case '0':
        case '1':
        case '2':
        case '3':
        case '4':
        case '5':
        case '6':
        case '7':
        case '8':
        case '9':
        case 'e':
        case 'E':
        case '+':
        case '-':
        case '.':
        {
            return YES;
        }
        default:
        {
            return NO;
        }
    }
}

static inline NSString *FXreadString(char *buffer, NSInteger sequenceLength, NSInteger index, NSInteger length)
{
    if (length - index >= sequenceLength)
    {
        char *sequence = malloc(sequenceLength);
        for (NSInteger i = 0; i < sequenceLength; i++)
        {
            char character = buffer[i + index];
            sequence[i] = character;
        }
        
        NSString *string = [[NSString alloc] initWithBytesNoCopy:sequence length:sequenceLength encoding:NSUTF8StringEncoding freeWhenDone:YES];
        
#if !__has_feature(objc_arc)
        
        [string autorelease];
        
#endif
        
        return string;
    }
    return nil;
}

static inline BOOL FXmatchesString(char *buffer, const char *string, NSInteger index, NSInteger length)
{
    for (NSInteger i = 0; ; i++)
    {
        char character = string[i];
        if (character == 0)
        {
            return YES;
        }
        if (i + index == length || character != buffer[i + index])
        {
            return NO;
        }
    }
}

static inline void FXappendCharacter(unichar **buffer, unichar character, NSInteger *length, NSInteger *capacity)
{
    if (*length >= *capacity)
    {
        (*capacity) *= 2;
        unichar *_buffer = realloc(*buffer, sizeof(unichar) * (*capacity));
        if (_buffer)
        {
            *buffer = _buffer;
        }
        else
        {
            //failed
            return;
        }
    }
    (*buffer)[(*length) ++] = character;
}

id FXparseObject(char *buffer, NSInteger *index, NSInteger length, id<FXJSONDelegate> delegate)
{
    //skip whitespace
    for (NSInteger i = *index; i < length; i++)
    {
        char character = buffer[i];
        if (FXisWhiteSpace(character))
        {
            (*index)++;
        }
        else
        {
            break;
        }
    }
    
    char character = buffer[*index];
    switch (character)
    {
        case '{':
            return FXparseDictionary(buffer, index, length, delegate);
        case '[':
            return FXparseArray(buffer, index, length, delegate);
        case '"':
            return FXparseString(buffer, index, length);
        case 'n':
            return FXparseNull(buffer, index, length);
        case 't':
            return FXparseTrue(buffer, index, length);
        case 'f':
            return FXparseFalse(buffer, index, length);
        default:
            return FXparseNumber(buffer, index, length);
    }
}

id FXparseDictionary(char *buffer, NSInteger *index, NSInteger length, id<FXJSONDelegate> delegate)
{
    //constants
    enum
    {
        kStart,
        kKeyExpected,
        kColonExpected,
        kValueExpected,
        kCommaExpected,
        kFinish
    };
    
    //parser state
    int state = kStart;
    NSString *key;
    NSObject *object;
    
    //delegate methods
    BOOL delegateDidStart = [delegate respondsToSelector:@selector(didStartJSONObject)];
    BOOL delegateDidEnd = [delegate respondsToSelector:@selector(didEndJSONObject)];
    BOOL delegateKey = [delegate respondsToSelector:@selector(didFindJSONKey:)];
    BOOL delegateValue = [delegate respondsToSelector:@selector(didFindJSONValue:)];
    
    //parse input
    NSMutableDictionary *dictionary = nil;
    for (NSInteger i = *index; i < length; i++)
    {
        @autoreleasepool
        {
            char character = buffer[i];
            if (FXisWhiteSpace(character))
            {
                //white space
                continue;
            }
            switch (state)
            {
                case kKeyExpected:
                {
                    if (character == '}')
                    {
                        //end of dictionary (not technically allowed by spec)
                        if (delegateDidEnd)
                        {
                            [delegate didEndJSONObject];
                        }
                        state = kFinish;
                    }
                    else
                    {
                        //test for string
                        if ((key = FXparseString(buffer, &i, length)))
                        {
                            if (delegateKey) [delegate didFindJSONKey:key];
                            
                            //now we need the value
                            state = kColonExpected;
                        }
                        else
                        {
                            //invalid key, unrecoverable
                            return nil;
                        }
                    }
                    break;
                }
                case kColonExpected:
                {
                    if (character == ':')
                    {
                        //now for the value
                        state = kValueExpected;
                    }
                    else
                    {
                        //no key specified, unrecoverable
                        return nil;
                    }
                    break;
                }
                case kValueExpected:
                {
                    //test for types
                    if ((object = FXparseObject(buffer, &i, length, delegate)))
                    {
                        if (delegate)
                        {
                            if (delegateValue) [delegate didFindJSONValue:object];
                        }
                        else if (!FXJSON_OMIT_NULL_OBJECT_VALUES || object != [NSNull null])
                        {
                            //add object to dictionary
                            [dictionary setObject:object forKey:key];
                        }
                        state = kCommaExpected;
                    }
                    else
                    {
                        //unrecognised type, unrecoverable
                        return nil;
                    }
                    break;
                }
                case kCommaExpected:
                {
                    if (character == '}')
                    {
                        //end of dictionary
                        if (delegateDidEnd)
                        {
                            [delegate didEndJSONObject];
                        }
                        state = kFinish;
                    }
                    else if (character == ',')
                    {
                        //next key
                        state = kKeyExpected;
                    }
                    else
                    {
                        //unexpected delimiter, unrecoverable
                        return nil;
                    }
                    break;
                }
                case kStart:
                {
                    if (character == '{')
                    {
                        if (delegateDidStart)
                        {
                            [delegate didStartJSONObject];
                        }
                        dictionary = [NSMutableDictionary dictionary];
                        state = kKeyExpected;
                    }
                    else
                    {
                        //not a dictionary
                        return nil;
                    }
                    break;
                }
            }
            if (state == kFinish)
            {
                (*index) = i;
                break;
            }
        }
    }
    
    //unexpected end of file
    if (state != kFinish)
    {
        *index = length;
    }
    
    //return dictionary
    return dictionary;
}

id FXparseArray(char *buffer, NSInteger *index, NSInteger length, id<FXJSONDelegate> delegate)
{
    //constants
    enum
    {
        kStart,
        kValueExpected,
        kCommaExpected,
        kFinish
    };
    
    //parser state
    int state = kStart;
    
    //delegate methods
    BOOL delegateDidStart = [delegate respondsToSelector:@selector(didStartJSONArray)];
    BOOL delegateDidEnd = [delegate respondsToSelector:@selector(didEndJSONArray)];
    BOOL delegateValue = [delegate respondsToSelector:@selector(didFindJSONValue:)];
    
    //parse input
    NSMutableArray *array = nil;
    for (NSInteger i = *index; i < length; i++)
    {
        @autoreleasepool
        {
            char character = buffer[i];
            if (FXisWhiteSpace(character))
            {
                //white space
                continue;
            }
            switch (state)
            {
                case kValueExpected:
                {
                    if (character == ']')
                    {
                        //end of array (not technically allowed by spec)
                        if (delegateDidEnd)
                        {
                            [delegate didEndJSONArray];
                        }
                        state = kFinish;
                    }
                    else
                    {
                        //test for types
                        id object;
                        if ((object = FXparseObject(buffer, &i, length, delegate)))
                        {
                            if (delegate)
                            {
                                if (delegateValue) [delegate didFindJSONValue:object];
                            }
                            else if (!FXJSON_OMIT_NULL_ARRAY_VALUES || object != [NSNull null])
                            {
                                //add object to array
                                [array addObject:object];
                            }
                            state = kCommaExpected;
                        }
                        else
                        {
                            //unrecognised type, unrecoverable
                            return nil;
                        }
                    }
                    break;
                }
                case kCommaExpected:
                {
                    if (character == ']')
                    {
                        //end of array
                        if (delegateDidEnd)
                        {
                            [delegate didEndJSONArray];
                        }
                        state = kFinish;
                    }
                    else if (character == ',')
                    {
                        //next value
                        state = kValueExpected;
                    }
                    else
                    {
                        //unexpected delimiter, unrecoverable
                        return nil;
                    }
                    break;
                }
                case kStart:
                {
                    if (character == '[')
                    {
                        if (delegateDidStart)
                        {
                            [delegate didStartJSONArray];
                        }
                        array = [NSMutableArray array];
                        state = kValueExpected;
                    }
                    else
                    {
                        //not an array
                        return nil;
                    }
                    break;
                }
            }
            if (state == kFinish)
            {
                (*index) = i;
                break;
            }
        }
    }
    
    //unexpected end of file
    if (state != kFinish)
    {
        *index = length;
    }
    
    //return array
    return array;
}

id FXparseString(char *buffer, NSInteger *index, NSInteger length)
{
    //constants
    enum
    {
        kStart,
        kNormal,
        kEscaped,
        kFinish
    };
    
    //parser state
    int state = kStart;
    NSInteger parsedLength = 0;
    NSInteger capacity = 16;
    
    //parse input
    unichar *output = NULL;
    for (NSInteger i = *index; i < length; i++)
    {
        char character = buffer[i];
        switch (state)
        {
            case kNormal:
            {
                if (character == '"')
                {
                    //end of string
                    state = kFinish;
                }
                else if (character == '\\')
                {
                    //escape character
                    state = kEscaped;
                }
                else
                {
                    //output character
                    FXappendCharacter(&output, character, &parsedLength, &capacity);
                }
                break;
            }
            case kEscaped:
            {
                switch (character)
                {
                    case '\\':
                    case '/':
                    case '"':
                        FXappendCharacter(&output, character, &parsedLength, &capacity);
                        break;
                    case 'b':
                        FXappendCharacter(&output, '\b', &parsedLength, &capacity);
                        break;
                    case 'f':
                        FXappendCharacter(&output, '\f', &parsedLength, &capacity);
                        break;
                    case 'n':
                        FXappendCharacter(&output, '\n', &parsedLength, &capacity);
                        break;
                    case 'r':
                        FXappendCharacter(&output, '\r', &parsedLength, &capacity);
                        break;
                    case 't':
                        FXappendCharacter(&output, '\t', &parsedLength, &capacity);
                        break;
                    case 'u':
                    {
                        @autoreleasepool
                        {
                            NSString *literal = FXreadString(buffer, 4, i + 1, length);
                            if (literal)
                            {
                                i += 4;
                                uint32_t c = 0;
                                NSScanner *scanner = [NSScanner scannerWithString:literal];
                                [scanner scanHexInt:&c];
                                
                                if (c <= 0xffff)
                                {
                                    FXappendCharacter(&output, c, &parsedLength, &capacity);
                                }
                                else
                                {
                                    //convert character to surrogate pair
                                    uint16_t x = (uint16_t)c;
                                    uint16_t u = (c >> 16) & ((1 << 5) - 1);
                                    uint16_t w = (uint16_t)u - 1;
                                    unichar high = 0xd800 | (w << 6) | x >> 10;
                                    unichar low = (uint16_t)(0xdc00 | (x & ((1 << 10) - 1)));
                                    
                                    FXappendCharacter(&output, high, &parsedLength, &capacity);
                                    FXappendCharacter(&output, low, &parsedLength, &capacity);
                                }
                            }
                        }
                        break;
                    }
                    default:
                    {
                        //not technically supported by spec but treat as literal
                        FXappendCharacter(&output, character, &parsedLength, &capacity);
                        break;
                    }
                }
                state = kNormal;
                break;
            }
            case kStart:
            {
                if (character == '"')
                {
                    output = malloc(sizeof(unichar) * capacity);
                    state = kNormal;
                }
                else
                {
                    //not a string
                    return nil;
                }
                break;
            }
        }
        if (state == kFinish)
        {
            (*index) = i;
            unichar *_output = parsedLength? realloc(output, sizeof(unichar) * parsedLength): NULL;
            if (_output)
            {
                output = _output;
            }
            else
            {
                //failed
                free(output);
                output = NULL;
            }
            break;
        }
    }
    
    //unexpected end of file
    if (state != kFinish)
    {
        *index = length;
    }
    
    //build string
    NSString *string = output? [[NSString alloc] initWithBytesNoCopy:output length:sizeof(unichar) * parsedLength encoding:NSUTF16LittleEndianStringEncoding freeWhenDone:YES]: nil;
    
#if !__has_feature(objc_arc)
    
    [string autorelease];
    
#endif
    
    return string;
}

id FXparseNumber(char *buffer, NSInteger *index, NSInteger length)
{
    //parser state
    NSInteger parsedLength = 0;
    
    //parse input
    for (NSInteger i = *index; i < length; i++)
    {
        char character = buffer[i];
        if (FXisNumeric(character))
        {
            //part of number
            parsedLength++;
        }
        else
        {
            //end of number
            break;
        }
    }
    
    //grab digits as string
    NSString *string = [[NSString alloc] initWithBytesNoCopy:buffer + (*index) length:parsedLength encoding:NSUTF8StringEncoding freeWhenDone:NO];
    
    //parse number
    NSNumber *number = [NSNumber numberWithDouble:[string doubleValue]];
    
    //update index
    (*index) += parsedLength - 1;
    
#if !__has_feature(objc_arc)
    
    [string release];
    
#endif
    
    return number;
}

id FXparseTrue(char *buffer, NSInteger *index, NSInteger length)
{
    //test
    if (FXmatchesString(buffer, "true", *index, length))
    {
        (*index) += 3;
        return [NSNumber numberWithBool:YES];
    }
    
    //no match
    return nil;
}

id FXparseFalse(char *buffer, NSInteger *index, NSInteger length)
{    
    //test
    if (FXmatchesString(buffer, "false", *index, length))
    {
        (*index) += 4;
        return [NSNumber numberWithBool:NO];
    }
    
    //no match
    return nil;
}

id FXparseNull(char *buffer, NSInteger *index, NSInteger length)
{    
    //test
    if (FXmatchesString(buffer, "null", *index, length))
    {
        (*index) += 3;
        return [NSNull null];
    }
    
    //no match
    return nil;
}

void FXstripNulls(id object)
{
    if ([object isKindOfClass:[NSDictionary class]])
    {
        for (NSString *key in [object allKeys])
        {
            id value = [object objectForKey:key];
            if (value == [NSNull null])
            {
                [object removeObjectForKey:key];
            }
            else
            {
                FXstripNulls(value);
            }
        }
    }
    else if ([object isKindOfClass:[NSArray class]])
    {
        for (id value in object)
        {
            FXstripNulls(value);
        }
    }
}

+ (void)enumerateJSONData:(NSData *)data withDelegate:(id<FXJSONDelegate>)delegate
{
    NSInteger index = 0;
    NSInteger length = [data length];
    [delegate didStartJSONParsing];
    id object;
    if ((object = FXparseObject((char *)data.bytes, &index, length, delegate)))
    {
        if ([delegate respondsToSelector:@selector(didFindJSONValue:)])
        {
            [delegate didFindJSONValue:object];
        }
    }
    [delegate didEndJSONParsing];
}

+ (id)objectWithJSONEncodedString:(NSString *)string
{    
    return [self objectWithJSONData:[string dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:YES]];
}

+ (id)objectWithJSONData:(NSData *)data
{
    if (!data)
    {
        return nil;
    }
    
    if (FXJSON_USE_NSJSON_IF_AVAILABLE)
    {
        if ([NSJSONSerialization class])
        {
            NSJSONReadingOptions options = NSJSONReadingAllowFragments | NSJSONReadingMutableContainers;
            id object = [NSJSONSerialization JSONObjectWithData:data options:options error:NULL];
            if (FXJSON_OMIT_NULL_OBJECT_VALUES)
            {
                FXstripNulls(object);
            }
            return object;
        }
    }
    
    NSInteger index = 0;
    NSInteger length = [data length];
    return FXparseObject((char *)data.bytes, &index, length, nil);
}

@end

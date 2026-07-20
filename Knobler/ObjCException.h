//
//  ObjCException.h
//  Knobler
//
//  Ponte mínima pra capturar NSException do Objective-C no Swift. Alguns caminhos
//  do AVFoundation (ex.: AVAudioEngine.installTap com um device de entrada de
//  formato "estranho") lançam NSException — e `do/catch` de Swift NÃO pega isso,
//  então o app aborta. Envolver a chamada arriscada aqui converte em NSError.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ObjCException : NSObject

/// Roda `block`. Retorna YES se completou; NO + preenche `error` se lançou NSException.
+ (BOOL)catching:(NS_NOESCAPE void (^)(void))block
           error:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END

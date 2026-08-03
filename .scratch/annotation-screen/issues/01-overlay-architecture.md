Type: grilling
Status: resolved

## Question

Qual arquitetura de janelas, níveis, telas e captura de eventos permite desenhar sobre a tela inteira sem vazar cliques/teclas para o aplicativo apresentado, mantendo o overlay independente das janelas do notch e compatível com múltiplos monitores?

## Answer

Criar um `AnnotationController` AppKit, separado do `NotchViewModel`, que gerencia uma janela borderless por `NSScreen`/`CGDirectDisplayID`. Cada janela será um `NSPanel` transparente, sem sombra, com `.canJoinAllSpaces`, `.fullScreenAuxiliary`, `.stationary` e `.ignoresCycle`, em nível acima das janelas normais e abaixo do `CGShieldingWindowLevel` usado pelo Descanso. O overlay fica ordenado para fora quando inativo; quando ativo, `ignoresMouseEvents = false`, cobre a tela inteira e consome os eventos de mouse, impedindo que cliques caiam no aplicativo apresentado.

O desenho será uma camada SwiftUI/AppKit hospedada na janela, enquanto o controlador mantém o estado compartilhado por display. A ativação do Control direito usará um único `CGEventTap` global, seguindo o padrão já existente em `VolumeHUDController`; monitores globais comuns não podem suprimir a tecla. O tap deve reconhecer `flagsChanged`, distinguir o Control direito e encaminhar apenas transições de ativação ao controller. O evento de desenho em si será tratado pela view da janela ativa.

O overlay não usará modo quiosque, `NSApp.presentationOptions` nem alteração permanente da activation policy: a feature precisa coexistir com Dock, menu bar, Cmd-Tab e o app apresentado. Ao sair, as janelas serão fechadas/ocultadas e o foco retorna ao aplicativo anterior. O ciclo de telas seguirá `placeWindows()`/`screensChanged()` do app, mas com uma store única e coordenadas locais por display para evitar duplicação de estado.

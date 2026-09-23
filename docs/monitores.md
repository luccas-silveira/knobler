# Monitores

Peça opcional para controlar uma tela por vez no notch. Instale em
**Ajustes → Peças → Monitores**; a seção participa da ordenação e fixação
existentes. Conectar uma tela não abre o notch.

## No notch

O seletor mostra as telas disponíveis. Ao abrir, a seleção acompanha a tela
daquele notch; uma escolha manual permanece enquanto o painel estiver aberto.
O brilho é o controle principal. Volume e mudo dependem do monitor; contraste
fica na área expansível. A engrenagem abre os ajustes da tela selecionada.
Arrastar um slider mantém o painel aberto e não gera um segundo HUD.

“Escurecimento por software” indica que o Knobler reduz a imagem por gamma ou
por uma sobreposição. No modo automático, o controle físico tem preferência;
o software permite escurecer abaixo do mínimo físico ou controlar telas sem
DDC. Preto total começa desabilitado.

Controles sem suporte mostram a limitação. Uma falha de comunicação não
confirma o valor como aplicado: use **Tentar novamente**. O suporte depende
também do cabo, adaptador, dock, entrada e firmware do monitor.

## Teclado e sincronização

- Brilho acompanha a tela sob o cursor, respeitando a participação no teclado
  configurada para cada tela. O HUD identifica a tela afetada e não abre o painel.
- Volume e mudo acompanham a saída de áudio ativa. Se o vínculo com um monitor
  não for inequívoco, configure a associação explicitamente; o Knobler não
  envia o comando a vários monitores por tentativa.
- O volume do painel controla explicitamente o monitor selecionado.
- A sincronização começa desligada. Quando ligada nas telas participantes,
  replica a diferença de brilho, preservando níveis relativos, inclusive nas
  mudanças observadas em telas Apple. Os limites individuais continuam valendo.
- Atalhos personalizados começam sem combinação. A habilitação do controle é
  independente da preferência de mostrar HUD.

## Ajustes e persistência

Cada monitor tem nome, participação no teclado, saída de áudio associada,
modo automático/hardware/software, método gamma/overlay e sincronização.
A área avançada inclui calibração mínima/máxima, curva, inversão, comandos DDC,
atrasos, tentativas, suporte a mudo e opção de preto total.

O início lê os valores físicos; restaurar os últimos valores é uma opção.
As preferências ficam no domínio `com.zoi.knobler`, com prefixo próprio e
identidade persistente da tela. Preferências do aplicativo MonitorControl não
são importadas. Não há novas rotas HTTP nem comunicação de rede nesta peça.

Desativar a peça preserva ajustes, cancela trabalho pendente, remove observadores
e atalhos e desfaz o escurecimento aplicado pelo Knobler. Os controles de teclado
voltam ao comportamento anterior.

## Backend e créditos

Baseado no código fornecido do **MonitorControl 4.4.0**, incluindo os transportes
Arm64DDC e IntelDDC. As fontes necessárias ficam em `Vendor/MonitorControl`;
a aplicação não depende da pasta de importação. Licença, origem e adaptações
estão em [Vendor/PROVENANCE.md](../Vendor/PROVENANCE.md).

A apresentação, o ciclo de vida da peça e o HUD pertencem ao Knobler. Menus,
janela de preferências, updater e login helper do MonitorControl não são usados.

## Validação

Os self-checks e snapshots usam dados sintéticos: não ajustam telas físicas.
Os seis cenários visuais cobrem tela interna, DDC completo, software apenas,
múltiplas telas, contraste expandido e erro de comunicação.

**Validação física pendente:** não foi executada nesta implementação, em Intel
nem em Apple Silicon. Build e simulações não comprovam a compatibilidade de
um monitor, dock ou saída de áudio. Antes de considerar uma configuração
validada, registrar Mac/arquitetura, macOS, modelo da tela, conexão/adaptador e:

1. Ler brilho inicial sem alteração; ajustar brilho, contraste, volume e mudo.
2. Testar calibração, limites e escurecimento abaixo do mínimo; desativar a peça
   e confirmar remoção de gamma/overlay.
3. Mover o cursor entre telas, conferir destino e identificação dos HUDs;
   trocar a saída de áudio e testar associação explícita e ambígua.
4. Ligar sincronização com níveis diferentes e testar mudanças nas telas Apple.
5. Suspender/retomar e desconectar/reconectar durante alterações rápidas.
6. Confirmar falha visível, repetição do mesmo valor e resposta das animações,
   do ditado e dos demais HUDs durante comandos DDC.

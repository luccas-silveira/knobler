//
//  WebhookPresets.swift
//  Knobler
//
//  As receitas de configuração de webhook, em literal Swift (decisão 006: bundle,
//  não recurso JSON nem override servido pelo relay — literal dá erro de
//  compilação em vez de erro de usuário, e funciona offline).
//
//  Grão = CAMINHO, não serviço: o GoHighLevel são dois sistemas incompatíveis e o
//  ClickUp tem dois caminhos. São quatro; o do Notion espera a captura real
//  (ticket 011 / 022) — nenhum preset entra escrito só pela documentação.
//
//  O preset NUNCA sobrescreve nem filtra payload real: quando a assinatura mínima
//  não bate com o que chegou, o mapa sugerido é desligado e o aviso é
//  não-bloqueante. Reaplicar é sempre manual.
//
//  Sem SwiftUI de propósito: o gate (`tools/presetcheck.swift`) compila só este
//  arquivo e o `WebhookTemplate.swift`.
//

import Foundation

/// Um campo do card que o mapeamento preenche.
enum TemplateField: String, Hashable, CaseIterable { case title, body, url, id }

/// Sugestão para um campo. Serve pra duas coisas ao mesmo tempo: virar texto na
/// tela ("de onde sai o título") e ser a semente do auto-mapeamento (005), que
/// casa o `template` contra a árvore do payload real.
///
/// ponytail: 006 previa `mapaFixo` e `dicasDeForma` separados; nos quatro
/// caminhos capturados os dois seriam idênticos (as chaves são literais), então
/// é uma lista só + `mapaAplicavelSemPayload`. O Notion, cujos caminhos têm
/// buraco (`properties.<sua propriedade>`), entra com a flag em `false`.
struct DicaDeForma {
    let campo: TemplateField
    let template: String
    let explicacao: String
}

struct WebhookPreset {
    let id: String
    /// Monotônica por preset (não é a versão do app). Bump só quando o conteúdo
    /// muda de um jeito que valha reaplicar: `_origem.versao < versao` é a
    /// condição exata do aviso de "o preset mudou".
    let versao: Int
    let servico: String          // agrupa o Form do passo Serviço
    let caminho: String
    let icone: String            // SF Symbol
    let instrucao: String        // onde colar o link, do lado do serviço
    let ressalva: String?
    /// Caminhos que TODOS têm que existir no payload pra reconhecer o caminho.
    /// Nunca o exemplo inteiro — 1 ou 2 chaves discriminantes.
    let assinatura: [String]
    let dicas: [DicaDeForma]
    /// `true` = as dicas são caminhos literais e podem virar mapa antes do
    /// primeiro POST. `false` = têm buraco pra preencher com o payload real.
    let mapaAplicavelSemPayload: Bool
    /// Fonte "exemplo embutido" do editor: payload real, podado do ruído.
    let exemplo: String

    var mapaSugerido: [TemplateField: String] {
        Dictionary(uniqueKeysWithValues: dicas.map { ($0.campo, $0.template) })
    }
}

enum WebhookPresets {
    static let todos: [WebhookPreset] = [ghlMarketplace, ghlWorkflow, clickupAPI, clickupAutomacao]

    static func by(id: String) -> WebhookPreset? { todos.first { $0.id == id } }

    /// O primeiro preset cuja assinatura mínima bate com o payload. Nenhum = nil
    /// (o payload real segue valendo; quem some é o preset).
    static func reconhece(_ payload: JSONValue?) -> WebhookPreset? {
        todos.first { p in p.assinatura.allSatisfy { node(at: $0, payload) != nil } }
    }

    // MARK: - GoHighLevel

    static let ghlMarketplace = WebhookPreset(
        id: "ghl-marketplace",
        versao: 1,
        servico: "GoHighLevel",
        caminho: "App do Marketplace",
        icone: "shippingbox",
        instrucao: """
        No app do Marketplace, em Settings → Webhooks, cole o link do perfil como \
        URL de destino e assine os eventos que interessam (ContactCreate, \
        InboundMessage, OpportunityStageUpdate…).
        """,
        ressalva: """
        Quase todo campo é opcional: um contato criado por SMS chega só com \
        telefone. E o corpo muda por evento — este mapa é o de contato.
        """,
        assinatura: ["type", "locationId"],
        dicas: [
            .init(campo: .title, template: "{{name}}",
                  explicacao: "nome já montado do contato"),
            .init(campo: .body, template: "{{type}} · {{email}}",
                  explicacao: "o evento e o e-mail do contato"),
            .init(campo: .url,
                  template: "https://app.gohighlevel.com/v2/location/{{locationId}}/contacts/detail/{{id}}",
                  explicacao: "deep link montado com a location e o id do contato"),
            .init(campo: .id, template: "{{webhookId}}",
                  explicacao: "UUID por entrega — é a chave de dedupe do GHL"),
        ],
        mapaAplicavelSemPayload: true,
        exemplo: """
        {
          "type": "ContactCreate",
          "webhookId": "881b9415-5d35-4ff1-a667-0545b80b96c0",
          "timestamp": "2026-08-04T12:41:02.193Z",
          "locationId": "ve9EPM428h8vShlRW1KT",
          "id": "nmFmQEsNgz6AVpgLVUJ0",
          "name": "John Deo",
          "firstName": "John",
          "lastName": "Deo",
          "email": "john.deo@example.com",
          "phone": "+919509597501",
          "source": "xyz form",
          "dateAdded": "2026-08-04T12:41:02.193Z",
          "tags": ["lead", "site"]
        }
        """
    )

    static let ghlWorkflow = WebhookPreset(
        id: "ghl-workflow",
        versao: 1,
        servico: "GoHighLevel",
        caminho: "Ação Webhook num workflow",
        icone: "arrow.triangle.branch",
        instrucao: """
        No workflow, adicione a ação Webhook (a gratuita), método POST, e cole o \
        link do perfil na URL. Publique o workflow antes de testar.
        """,
        ressalva: """
        O corpo segue o gatilho: um gatilho de tag manda o contato, outro manda \
        outra coisa. Não há assinatura nos headers — o link é o único segredo — \
        nem id de entrega, então não existe dedupe.
        """,
        assinatura: ["location.id", "workflow.id"],
        dicas: [
            .init(campo: .title, template: "{{full_name}}",
                  explicacao: "nome completo do contato"),
            .init(campo: .body, template: "{{workflow.name}} · {{email}}",
                  explicacao: "o workflow que disparou e o e-mail"),
            .init(campo: .url,
                  template: "https://app.gohighlevel.com/v2/location/{{location.id}}/contacts/detail/{{contact_id}}",
                  explicacao: "dois tokens no mesmo campo: a URL não vem pronta"),
            .init(campo: .id, template: "{{contact_id}}",
                  explicacao: "não há id de entrega; o do contato é a melhor aproximação"),
        ],
        mapaAplicavelSemPayload: true,
        exemplo: """
        {
          "contact_id": "gxGfB9wxEy3anxbHB4nT",
          "first_name": "Knobler",
          "last_name": "Captura012",
          "full_name": "Knobler Captura012",
          "email": "knobler.captura012@example.com",
          "tags": "knobler-captura",
          "country": "BR",
          "date_created": "2026-08-04T14:53:09.703Z",
          "contact_type": "lead",
          "location": {
            "name": "adriN's Playground",
            "city": "Joinville",
            "state": "Santa Catarina",
            "id": "t9Ww7bY1xJJ6ThFHZVPC"
          },
          "workflow": { "id": "d325be72-ae1d-490a-b6e7-62b404ecd35b", "name": "Tag nova" },
          "customData": { "origem_knobler": "captura-012" }
        }
        """
    )

    // MARK: - ClickUp

    static let clickupAPI = WebhookPreset(
        id: "clickup-api",
        versao: 1,
        servico: "ClickUp",
        caminho: "Webhook de API",
        icone: "chevron.left.forwardslash.chevron.right",
        instrucao: """
        Registre o webhook por API (POST /team/{team_id}/webhook) com o link do \
        perfil como endpoint e os eventos que interessam.
        """,
        ressalva: """
        Este caminho NÃO manda o nome da tarefa — só o id e o histórico da \
        mudança. Se quiser o nome no card, use a automação "Call webhook".
        """,
        assinatura: ["event", "task_id"],
        dicas: [
            .init(campo: .title, template: "{{event}}",
                  explicacao: "o nome da tarefa não vem; sobra o tipo de evento"),
            .init(campo: .body, template: "{{history_items.0.comment.text_content}}",
                  explicacao: "texto puro do comentário (só em taskCommentPosted)"),
            .init(campo: .url, template: "https://app.clickup.com/t/{{task_id}}",
                  explicacao: "a URL é montada; não vem no payload"),
            .init(campo: .id, template: "{{event}}:{{history_items.0.id}}",
                  explicacao: "id do registro de histórico — único por mudança"),
        ],
        mapaAplicavelSemPayload: true,
        exemplo: """
        {
          "event": "taskCommentPosted",
          "task_id": "1vj38vv",
          "webhook_id": "7fa3ec74-69a8-4530-a251-8a13730bd204",
          "history_items": [
            {
              "id": "2800803631413624919",
              "date": "1642737045116",
              "field": "comment",
              "user": { "id": 183, "username": "John", "email": "john@example.com" },
              "comment": {
                "id": "648893191",
                "text_content": "comment abc1234\\n"
              }
            }
          ]
        }
        """
    )

    static let clickupAutomacao = WebhookPreset(
        id: "clickup-automacao",
        versao: 1,
        servico: "ClickUp",
        caminho: "Automação \"Call webhook\"",
        icone: "bolt.badge.automatic",
        instrucao: """
        Na lista ou no espaço, Automatizar → nova automação, gatilho à escolha e \
        ação "Webhook de chamada" (a atual, não a "(antigo)"). Cole o link do \
        perfil na URL.
        """,
        ressalva: """
        Hierarquia, status e responsável vêm só como ids opacos — sem nome. As \
        datas de `time_mgmt` estão em epoch de milissegundos: use o filtro \
        `| data`.
        """,
        assinatura: ["auto_id", "payload.id"],
        dicas: [
            .init(campo: .title, template: "{{payload.name}}",
                  explicacao: "nome da tarefa"),
            .init(campo: .body, template: "{{payload.text_content}}",
                  explicacao: "descrição já limpa (payload.content é Quill escapado)"),
            .init(campo: .url, template: "https://app.clickup.com/t/{{payload.id}}",
                  explicacao: "a URL é montada; não vem no payload"),
            .init(campo: .id, template: "{{payload.id}}",
                  explicacao: "id da tarefa"),
        ],
        mapaAplicavelSemPayload: true,
        exemplo: """
        {
          "auto_id": "d8e9382d-99ec-4d79-bc4a-9646bd2a0e46:main",
          "trigger_id": "6954dd13-7db2-4817-9fe7-dba3d463f26c",
          "date": "2026-08-04T15:04:00.876Z",
          "payload": {
            "id": "86ajvvnpa",
            "name": "Knobler captura 010",
            "content": "{\\"ops\\":[{\\"insert\\":\\"Tarefa de teste.\\\\n\\"}]}",
            "text_content": "Tarefa de teste.",
            "priority": "2",
            "status_id": "p901313929324_0h9D6Zm2",
            "workspace_id": "9007072151",
            "subcategory": "901327950786",
            "time_mgmt": { "date_created": "1785855839804", "due_date": "1786384800000" },
            "ownership": { "owner": 81976356, "creator": 81976356, "source": "api" },
            "lists": [ { "list_id": "901327950786", "type": "home" } ]
          }
        }
        """
    )
}

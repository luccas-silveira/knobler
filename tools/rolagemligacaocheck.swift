// Gate de ligação da rolagem: o `handleScroll` (Knobler/KnoblerApp.swift, que
// o ./tools/check.sh não compila) diz ao `NotchGesture.acao` quando o evento
// encerra o gesto.
//
//   xcrun swiftc -parse-as-library -swift-version 5 \
//     tools/rolagemligacaocheck.swift \
//     -o /tmp/rolagemligacaocheck && /tmp/rolagemligacaocheck
//
// Roda da raiz do repo (o check.sh faz `cd` para lá): lê o fonte como texto.
//
// O rolagemcheck prova a regra pura (`fim: true` sempre repassa); não prova
// que o monitor de verdade entrega o `fim` certo. Sem isso a lista do card
// continua sem saber que os dedos saíram. Confere, dentro do corpo de
// `func handleScroll(`:
//   - a chamada `NotchGesture.acao(` passa o argumento `fim:`;
//   - o valor não é o literal `true` nem `false`;
//   - o valor sai das fases do evento: a expressão passada em `fim:`, somada
//     aos `let`/`var` do próprio `handleScroll` em que ela se apoia (seguidos
//     em cadeia), lê `event.phase` e `event.momentumPhase` e cita `.ended` e
//     `.cancelled`.
// Vale qualquer forma disso: `let fim = event.phase.contains(.ended) || …`
// antes da chamada, a expressão direto no argumento, ou um conjunto
// `[.ended, .cancelled]` num `let` à parte. Comentário e miolo de string não
// contam como ligação, e fase citada num `let` que o `fim:` não usa também não.
//
// Cada falta imprime `FALHOU: <o quê>` e o gate sai 1. Antes da checagem real,
// um autoteste num fonte de mentira prova que a verificação reprova.

import Foundation

// MARK: - leitura do fonte

/// O fonte com comentário e miolo de string trocados por espaço, caractere a
/// caractere: chave ou parêntese dentro deles não entra na conta de quem casa.
private func soCodigo(_ fonte: String) -> [Character] {
    var c = Array(fonte)
    var i = 0
    func apagar(_ j: Int) { if c[j] != "\n" { c[j] = " " } }
    while i < c.count {
        if c[i] == "/", i + 1 < c.count, c[i + 1] == "/" {
            while i < c.count, c[i] != "\n" { apagar(i); i += 1 }
        } else if c[i] == "/", i + 1 < c.count, c[i + 1] == "*" {
            while i < c.count, !(c[i] == "*" && i + 1 < c.count && c[i + 1] == "/") { apagar(i); i += 1 }
            if i < c.count { apagar(i); apagar(i + 1); i += 2 }
        } else if c[i] == "\"" {
            i += 1
            while i < c.count, c[i] != "\"", c[i] != "\n" {
                if c[i] == "\\", i + 1 < c.count { apagar(i); i += 1 }
                apagar(i); i += 1
            }
            i += 1
        } else {
            i += 1
        }
    }
    return c
}

/// Posição de quem fecha o `(`, `[` ou `{` aberto em `abre`; `nil` se não fecha.
private func fechamento(_ c: [Character], _ abre: Int) -> Int? {
    var nivel = 0
    var i = abre
    while i < c.count {
        if "([{".contains(c[i]) { nivel += 1 }
        if ")]}".contains(c[i]) {
            nivel -= 1
            if nivel == 0 { return i }
        }
        i += 1
    }
    return nil
}

private func posicao(_ c: [Character], de alvo: String, apos inicio: Int, ate fim: Int) -> Int? {
    let a = Array(alvo)
    guard !a.isEmpty, inicio >= 0, fim - a.count >= inicio else { return nil }
    for i in inicio...(fim - a.count) where Array(c[i..<(i + a.count)]) == a { return i }
    return nil
}

private func ehDeNome(_ ch: Character) -> Bool { ch.isLetter || ch.isNumber || ch == "_" }

private func aparado(_ c: ArraySlice<Character>) -> String {
    String(c).trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Os nomes soltos de um trecho (`fim`, `inercia`, `event`…): identificador
/// que não vem depois de um ponto, ou seja, não é membro de ninguém.
private func nomes(_ trecho: String) -> [String] {
    let c = Array(trecho)
    var saida: [String] = []
    var i = 0
    while i < c.count {
        guard ehDeNome(c[i]), !c[i].isNumber else { i += 1; continue }
        let inicio = i
        while i < c.count, ehDeNome(c[i]) { i += 1 }
        if inicio == 0 || c[inicio - 1] != "." { saida.append(String(c[inicio..<i])) }
    }
    return saida
}

/// As declarações `let <nome>`/`var <nome>` entre `inicio` e `limite`, cada uma
/// com a instrução inteira (segue pela linha de baixo enquanto ela continuar a
/// expressão: parêntese aberto, linha terminando ou começando em operador).
private func declaracoes(de nome: String, em c: [Character], apos inicio: Int, ate limite: Int,
                         fimDoCorpo: Int) -> [String] {
    let continua: Set<Character> = ["|", "&", "?", ":", ".", "+", "-", "*", "/", "=", "<", ">", ","]
    var saida: [String] = []
    var busca = inicio
    while busca < limite {
        let l = posicao(c, de: "let", apos: busca, ate: limite)
        let v = posicao(c, de: "var", apos: busca, ate: limite)
        guard let p = [l, v].compactMap({ $0 }).min() else { break }
        busca = p + 3
        guard p == 0 || !ehDeNome(c[p - 1]), busca < limite, c[busca].isWhitespace else { continue }
        var i = busca
        while i < limite, c[i].isWhitespace { i += 1 }
        let n = Array(nome)
        guard i + n.count <= limite, Array(c[i..<(i + n.count)]) == n,
              i + n.count >= c.count || !ehDeNome(c[i + n.count]) else { continue }
        // a instrução: até a quebra de linha em que a expressão acaba
        var nivel = 0
        var j = i
        var ultimo: Character = " "
        while j < fimDoCorpo {
            let ch = c[j]
            if "([{".contains(ch) { nivel += 1 }
            if ")]}".contains(ch) { nivel -= 1; if nivel < 0 { break } }
            if ch == ";" && nivel == 0 { break }
            if ch == "\n" && nivel == 0 {
                var k = j
                while k < fimDoCorpo, c[k].isWhitespace { k += 1 }
                let proximo: Character = k < fimDoCorpo ? c[k] : " "
                if !continua.contains(ultimo) && !continua.contains(proximo) { break }
            }
            if !ch.isWhitespace { ultimo = ch }
            j += 1
        }
        saida.append(String(c[p..<j]))
    }
    return saida
}

// MARK: - a verificação

/// O que falta na ligação; vazio = ligado.
private func faltas(_ fonte: String) -> [String] {
    let c = soCodigo(fonte)
    let assinatura = "func handleScroll"
    guard let f = posicao(c, de: assinatura + "(", apos: 0, ate: c.count),
          let fechaAssinatura = fechamento(c, f + assinatura.count),
          let abre = posicao(c, de: "{", apos: fechaAssinatura, ate: c.count),
          let fecha = fechamento(c, abre)
    else { return ["sem `func handleScroll(`"] }

    let alvo = "NotchGesture.acao"
    guard let chamada = posicao(c, de: alvo + "(", apos: abre, ate: fecha),
          let fechaChamada = fechamento(c, chamada + alvo.count)
    else { return ["o `handleScroll` não chama `NotchGesture.acao(`"] }

    // os argumentos da chamada, separados pelas vírgulas de fora
    var valor: String?
    var nivel = 0
    var inicio = chamada + alvo.count + 1
    for i in inicio...fechaChamada {
        let ch = c[i]
        if "([{".contains(ch) { nivel += 1 }
        if ")]}".contains(ch), i != fechaChamada { nivel -= 1 }
        guard (ch == "," && nivel == 0) || i == fechaChamada else { continue }
        let argumento = aparado(c[inicio..<i])
        inicio = i + 1
        guard argumento.hasPrefix("fim") else { continue }
        let resto = argumento.dropFirst(3).trimmingCharacters(in: .whitespacesAndNewlines)
        if resto.hasPrefix(":") {
            valor = resto.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    guard let valor else {
        return ["a chamada de `NotchGesture.acao(` no `handleScroll` não passa `fim:` — o evento que encerra o gesto segue sendo engolido"]
    }
    if valor == "true" || valor == "false" {
        return ["o `handleScroll` passa o literal `fim: \(valor)`; o `fim` tem que sair das fases do evento"]
    }

    // a expressão do `fim:` e os `let`/`var` do handleScroll em que ela se apoia
    var texto = valor
    var vistos: Set<String> = []
    var fila = nomes(valor)
    while let nome = fila.popLast() {
        guard vistos.insert(nome).inserted else { continue }
        for d in declaracoes(de: nome, em: c, apos: abre, ate: chamada, fimDoCorpo: fecha) {
            texto += "\n" + d
            fila += nomes(d)
        }
    }

    var saida: [String] = []
    for (pedaco, porque) in [
        ("event.phase", "o fim dos dedos no trackpad"),
        ("event.momentumPhase", "o fim da inércia"),
        (".ended", "o gesto que termina"),
        (".cancelled", "o gesto cancelado"),
    ] where !contem(texto, pedaco) {
        saida.append("o `fim:` do `handleScroll` (`\(valor)`) não vem de `\(pedaco)` (\(porque))")
    }
    return saida
}

/// `pedaco` aparece em `texto` sem ser o começo de um nome maior
/// (`event.phase` não casa com `event.phaseAntiga`).
private func contem(_ texto: String, _ pedaco: String) -> Bool {
    var resto = Substring(texto)
    while let r = resto.range(of: pedaco) {
        if r.upperBound == resto.endIndex || !ehDeNome(resto[r.upperBound]) { return true }
        resto = resto[r.upperBound...]
    }
    return false
}

// MARK: - autoteste

private var falhasDoAutoteste = 0

/// Um KnoblerApp de mentira com o desenho do de verdade; `preparo` entra antes
/// da chamada e `argumento` no fim da lista de argumentos dela.
private func fonteFalso(preparo: String, argumento: String, sobra: String = "") -> String {
    let base = """
    final class AppDelegate {
        private func setupSwipeGestures() {
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) {
                [weak self] event in
                self?.handleScroll(event) ?? event
            }
        }

        private func handleScroll(_ event: NSEvent) -> NSEvent? {
            let novoGesto = NotchGesture.isGestureStart(
                began: event.phase == .began,
                momentum: !event.momentumPhase.isEmpty,
                sinceLastEvent: event.timestamp - lastScrollAt,
                previousInZone: lastScrollInZone,
                hasPhase: !event.phase.isEmpty || !event.momentumPhase.isEmpty)
            if novoGesto {
                scrollAccumX = 0
                scrollAccumY = 0
                scrollActed = false
            }

            // inércia não soma: ela chega depois dos dedos saírem
            let inercia = !event.momentumPhase.isEmpty
            if !inercia {
                scrollAccumX += event.scrollingDeltaX
                scrollAccumY += event.scrollingDeltaY
            }
            %PREPARO%
            // a decisão mora no NotchGesture; aqui só se aplica o resultado
            switch NotchGesture.acao(
                deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY,
                accumX: scrollAccumX, accumY: scrollAccumY,
                inercia: inercia, expandido: expanded,
                temMidia: media.state != nil, jaAgiu: scrollActed%ARGUMENTO%) {
            case .repassar:
                return event
            case .engolir:
                return nil // a janela de trás não rola de lado junto
            case .trocarSecao(let avancando):
                scrollActed = true
                vm.focarVizinho(avancando: avancando)
                return nil
            case .trocarFaixa(let proxima):
                scrollActed = true
                if proxima { media.nextTrack() } else { media.previousTrack() }
                return nil
            }
        }
        %SOBRA%
        @objc private func screensChanged() {
            placeWindows()
        }
    }
    """
    return base.replacingOccurrences(of: "%PREPARO%", with: preparo)
        .replacingOccurrences(of: "%ARGUMENTO%", with: argumento)
        .replacingOccurrences(of: "%SOBRA%", with: sobra)
}

/// `esperado == nil`: a ligação tem que passar. Senão, tem que reprovar com
/// uma falta que contenha o texto.
private func caso(_ nome: String, _ fonte: String, _ esperado: String?) {
    let f = faltas(fonte)
    if let esperado {
        if !f.contains(where: { $0.contains(esperado) }) {
            print("autoteste (\(nome)): devia reprovar com '\(esperado)'; faltas = \(f)")
            falhasDoAutoteste += 1
        }
    } else if !f.isEmpty {
        print("autoteste (\(nome)): ligação certa reprovada; faltas = \(f)")
        falhasDoAutoteste += 1
    }
}

private func autoteste() {
    let quatro = """
    // o evento que encerra o gesto sempre chega na lista
            let fim = event.phase.contains(.ended) || event.phase.contains(.cancelled)
                || event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled)
    """

    // --- formas certas ---
    caso("let fim com as quatro fases", fonteFalso(preparo: quatro, argumento: ", fim: fim"), nil)
    caso("fim: numa linha própria da chamada",
         fonteFalso(preparo: quatro, argumento: ",\n                fim: fim"), nil)
    caso("comparação com ==, linha terminando em ||",
         fonteFalso(preparo: """
         let fim = event.phase == .ended || event.phase == .cancelled ||
                     event.momentumPhase == .ended || event.momentumPhase == .cancelled
         """, argumento: ", fim: fim"), nil)
    caso("conjunto das fases num let à parte",
         fonteFalso(preparo: """
         let encerram: NSEvent.Phase = [.ended, .cancelled]
                 let fim = !event.phase.isDisjoint(with: encerram)
                     || !event.momentumPhase.isDisjoint(with: encerram)
         """, argumento: ", fim: fim"), nil)
    caso("expressão direto no argumento",
         fonteFalso(preparo: "", argumento: """
         ,
                         fim: !event.phase.intersection([.ended, .cancelled]).isEmpty
                             || !event.momentumPhase.intersection([.ended, .cancelled]).isEmpty
         """), nil)
    caso("variável com outro nome",
         fonteFalso(preparo: quatro.replacingOccurrences(of: "let fim", with: "let acabou"),
                    argumento: ", fim: acabou"), nil)

    // --- o que tem que reprovar ---
    caso("como está hoje: sem fim:", fonteFalso(preparo: "", argumento: ""), "não passa `fim:`")
    caso("fases calculadas e não passadas", fonteFalso(preparo: quatro, argumento: ""), "não passa `fim:`")
    caso("literal false", fonteFalso(preparo: "", argumento: ", fim: false"), "literal `fim: false`")
    caso("literal true", fonteFalso(preparo: "", argumento: ", fim: true"), "literal `fim: true`")
    caso("fases calculadas e literal passado",
         fonteFalso(preparo: quatro, argumento: ", fim: false"), "literal `fim: false`")
    caso("let fim = false",
         fonteFalso(preparo: "let fim = false", argumento: ", fim: fim"), "`event.phase`")
    caso("fim: inercia (toda a inércia viraria fim, e o fim dos dedos não)",
         fonteFalso(preparo: "", argumento: ", fim: inercia"), "`.ended`")
    caso("só a fase dos dedos",
         fonteFalso(preparo: "let fim = event.phase.contains(.ended) || event.phase.contains(.cancelled)",
                    argumento: ", fim: fim"), "`event.momentumPhase`")
    caso("só a fase da inércia",
         fonteFalso(preparo: "let fim = event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled)",
                    argumento: ", fim: fim"), "`event.phase`")
    caso("sem o gesto cancelado",
         fonteFalso(preparo: "let fim = event.phase.contains(.ended) || event.momentumPhase.contains(.ended)",
                    argumento: ", fim: fim"), "`.cancelled`")
    caso("sem o gesto que termina",
         fonteFalso(preparo: "let fim = event.phase.contains(.cancelled) || event.momentumPhase.contains(.cancelled)",
                    argumento: ", fim: fim"), "`.ended`")
    caso("fases num let que o fim: não usa",
         fonteFalso(preparo: quatro.replacingOccurrences(of: "let fim", with: "let acabou"),
                    argumento: ", fim: scrollActed"), "`.ended`")
    caso("cálculo só em comentário",
         fonteFalso(preparo: quatro.replacingOccurrences(of: "let fim", with: "// let fim")
                        .replacingOccurrences(of: "|| event.momentumPhase", with: "// || event.momentumPhase")
                        + "\nlet fim = scrollActed",
                    argumento: ", fim: fim"), "`.ended`")
    caso("fim: só em comentário na chamada",
         fonteFalso(preparo: quatro, argumento: " /* , fim: fim */"), "não passa `fim:`")
    caso("ligação certa em outra função, handleScroll como hoje",
         fonteFalso(preparo: "", argumento: "", sobra: """
         private func outra(_ event: NSEvent) {
                 let fim = event.phase.contains(.ended) || event.phase.contains(.cancelled)
                     || event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled)
                 _ = NotchGesture.acao(deltaX: 0, deltaY: 0, accumX: 0, accumY: 0, inercia: false,
                                       expandido: false, temMidia: false, jaAgiu: false, fim: fim)
             }
         """), "não passa `fim:`")
    caso("handleScroll sem a chamada",
         fonteFalso(preparo: "", argumento: "").replacingOccurrences(of: "NotchGesture.acao(", with: "decidir("),
         "não chama `NotchGesture.acao(`")
    caso("sem handleScroll",
         fonteFalso(preparo: quatro, argumento: ", fim: fim")
             .replacingOccurrences(of: "func handleScroll(", with: "func rolar("),
         "sem `func handleScroll(`")
}

// MARK: - main

@main
enum RolagemLigacaoCheck {
    static func main() {
        let app = "Knobler/KnoblerApp.swift"
        guard FileManager.default.fileExists(atPath: "tools/check.sh") else {
            print("FALHOU: rode da raiz do repo (o check.sh faz isso); cwd = \(FileManager.default.currentDirectoryPath)")
            exit(1)
        }

        autoteste()
        if falhasDoAutoteste > 0 {
            print("FALHOU: autoteste do rolagemligacaocheck")
            exit(1)
        }

        guard let fonte = try? String(contentsOfFile: app, encoding: .utf8) else {
            print("FALHOU: \(app) não existe")
            exit(1)
        }
        let f = faltas(fonte)
        for falta in f { print("FALHOU: \(app): \(falta)") }
        if !f.isEmpty { exit(1) }
        print("rolagemligacaocheck ok")
    }
}

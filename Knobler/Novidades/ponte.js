// Injetado como WKUserScript (.atDocumentEnd) pelo NovidadesWindow. O Swift
// define window.KNOBLER_CORPO antes deste script rodar.
(function () {
  var alvo = document.getElementById("conteudo");
  if (alvo && typeof window.KNOBLER_CORPO === "string") {
    alvo.innerHTML = window.KNOBLER_CORPO;
  }
  // Delegação: o corpo é injetado depois do parse, então listener por botão
  // não pegaria. Um listener no documento pega todos, inclusive os futuros.
  document.addEventListener("click", function (e) {
    var botao = e.target.closest("button[data-acao]");
    if (!botao) return;
    window.webkit.messageHandlers.app.postMessage({
      acao: botao.getAttribute("data-acao"),
      alvo: botao.getAttribute("data-alvo") || ""
    });
  });
})();

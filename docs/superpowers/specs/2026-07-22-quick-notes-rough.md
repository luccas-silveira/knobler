# 📝 Quick Notes — Rough Sketch

**Status**: Ideias abertas, não é spec ainda

## Entendimento inicial

Feature: Nota rápida (sticky) que aparece no notch.

### Comportamento descrito

- Abre/fecha colapsável (recolhe com mouse over, se fechar notch, se sair da nota)
- Reabre com mouse over
- Totalmente temporária — sem persistência
- Auto-delete após 15 min de inatividade (configurável)

### Perguntas abertas

1. **Quantas notas?** Uma só ou múltiplas simultâneas?
2. **Editável/Deletável?** User pode editar conteúdo? Deletar manualmente?
3. **Onde fica no notch?** Nova tab, estado do notch, ou overlay?
4. **Como abre?** Botão, hotkey (ex: ⌥N), ou API webhook?
5. **Sincroniza clipboard?** Pastas automático de clipboard ou manual?
6. **Formato** Plain text, markdown, ou rich text?
7. **Limite de tamanho?** Quantos caracteres max?
8. **Múltiplas instâncias?** Vários stickies abertos ao mesmo tempo?

## Próximos passos

- [ ] Conversar sobre as perguntas abertas
- [ ] Definir escopo (MVP vs full)
- [ ] Design de layout/UX
- [ ] Spec formal

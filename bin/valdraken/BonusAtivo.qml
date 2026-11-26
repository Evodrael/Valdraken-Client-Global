import QtQuick
import "qrc:/qt/qml/qmlcomponents/qml/"

// Bonus ativo de outfit e montaria no client Global (26/11/2026, test server).
// Carregado pelo PovTimer.qml (que o Loader do MinimapPanel.qml patcheado carrega de <bin>/valdraken/): um botao "B"
// abre o painel. O botao procura o "E" (modo expert) do painel de combate e se muda para o lado dele, acima do PvP;
// enquanto nao acha (ou com o painel de combate minimizado, que esconde o E) fica no canto do minimapa.
// O servidor e quem decide (data-otservbr-global/scripts/custom/bonus_ativo.lua):
//   leitura: <loginWebService>?bonusativo=<nome> devolve o JSON da tabela valdraken_bonus_ativo (o mesmo do opcode do OTC)
//   escrita: o comando "!bonus o<lookType>" / "!bonus m<clientid>" vai ao servidor pelo chatController.sendKeyword do
//            proprio client (o Chat tem objectName "chat"); sem ele, o comando fica escrito para o jogador mandar.
//   "!bonus ver" so regrava a tabela (a lista pode ter mudado desde o login).
Item {
  id: raiz
  width: 18; height: 18

  property var win: Window.window
  property string base: ""
  property var dados: null
  property var chatCtl: null
  property bool aberto: false
  property string aviso: ""
  property real liberaO: 0
  property real liberaM: 0
  property real agora: Date.now() / 1000
  readonly property color dourado: "#f2d38a"
  readonly property color cinza: "#c0c0c0"

  // O painel fica pendurado no contentItem da janela: sem isto ele continuava aberto por cima da tela de login
  // quando a conexao caia (a tela de jogo so e escondida, nao destruida).
  onVisibleChanged: if (!visible) aberto = false

  // ---------------------------------------------------------------- botao "B" ao lado do "E" do painel de combate
  property Item alvo: null   // o botao "E" (modo expert); volta a null sozinho se o painel for recriado
  property Item casa: null   // o Item do CombatControls que recebe o B (fora dos GridLayouts, para nao entrar no layout)
  readonly property bool noCombate: alvo !== null && casa !== null && alvo.visible

  function acharExpert(item, fundo) {
    if (!item || fundo > 80) return null;
    var s = item.sourceUp;
    if (typeof s === "string" && s.indexOf("/button-expert-") >= 0) return item;
    var filhos = item.children || [];
    for (var i = 0; i < filhos.length; i++) {
      var r = acharExpert(filhos[i], fundo + 1);
      if (r) return r;
    }
    return null;
  }

  function procurarExpert() {
    if (!win || !win.contentItem) return;
    var e = acharExpert(win.contentItem, 0);
    if (!e) return;
    var c = e.parent;
    while (c && c.parent && c.columns !== undefined) c = c.parent;
    if (!c) return;
    casa = c;
    alvo = e;
  }

  // posicao de um item dentro de um ancestral (le x, y e parent de cada degrau: a ligacao acompanha o layout)
  function posicao(it, ate) {
    var x = 0, y = 0, n = 0;
    while (it && it !== ate && n++ < 20) { x += it.x; y += it.y; it = it.parent; }
    return Qt.point(x, y);
  }

  Timer {
    interval: 1500; repeat: true; triggeredOnStart: true
    running: raiz.alvo === null || raiz.casa === null
    onTriggered: raiz.procurarExpert()
  }

  TibiaButton {
    id: botao
    parent: raiz.noCombate ? raiz.casa : raiz
    width: raiz.noCombate ? raiz.alvo.width : 18
    height: raiz.noCombate ? raiz.alvo.height : 18
    x: raiz.noCombate ? raiz.posicao(raiz.alvo, raiz.casa).x + raiz.alvo.width + 2 : 0
    y: raiz.noCombate ? raiz.posicao(raiz.alvo, raiz.casa).y : 0
    text: "B"
    tooltipText: "Bônus ativo de outfit e montaria"
    checkable: true
    useButtonShouldBeChecked: true
    buttonShouldBeChecked: raiz.aberto
    onClicked: raiz.alternar()
  }

  // ---------------------------------------------------------------- ligacao com o client e o servidor
  function nome() {
    var t = win ? win.title : "", i = t.lastIndexOf(" - ");
    return i < 0 ? "" : t.substring(i + 3);
  }

  function acharChat(item, fundo) {
    if (!item || fundo > 60) return null;
    if (item.objectName === "chat" && item.chatController) return item.chatController;
    var filhos = item.children || [];
    for (var i = 0; i < filhos.length; i++) {
      var r = acharChat(filhos[i], fundo + 1);
      if (r) return r;
    }
    return null;
  }

  function comando(txt) {
    if (!chatCtl && win) chatCtl = acharChat(win.contentItem, 0);
    if (chatCtl && typeof chatCtl.sendKeyword === "function") {
      chatCtl.sendKeyword(txt);
      return true;
    }
    return false;
  }

  function carregar() {
    var n = nome();
    if (base.length === 0 || n.length === 0) { aviso = "Não achei o personagem ou o endereço do servidor."; return; }
    var x = new XMLHttpRequest;
    x.onreadystatechange = function() {
      if (x.readyState !== 4) return;
      if (x.status !== 200) { raiz.aviso = "Servidor não respondeu (" + x.status + ")."; return; }
      try {
        var d = JSON.parse(x.responseText);
        if (!d || !d.o) { raiz.aviso = "Ainda sem dados: entre no jogo de novo."; return; }
        var t = Date.now() / 1000;
        raiz.liberaO = t + (d.wo || 0);
        raiz.liberaM = t + (d.wm || 0);
        raiz.dados = d;
      } catch (e) {
        raiz.aviso = "Resposta inválida do servidor.";
      }
    };
    x.open("GET", base + "?bonusativo=" + encodeURIComponent(n) + "&t=" + Date.now());
    x.send();
  }

  function alternar() {
    aberto = !aberto;
    if (aberto) {
      aviso = "";
      comando("!bonus ver");
      recarga.restart();
    }
  }

  function ativar(tipo, look) {
    var txt = "!bonus " + tipo + look;
    if (comando(txt)) {
      aviso = "";
    } else {
      aviso = "Mande no chat: " + txt;
    }
    recarga.restart();
  }

  function escolhido(tipo) {
    if (!dados) return -1;
    return tipo === "o" ? dados.ao : dados.am;
  }

  Timer { id: recarga; interval: 900; onTriggered: raiz.carregar() }
  Timer {
    interval: 1000; repeat: true; running: raiz.aberto
    onTriggered: raiz.agora = Date.now() / 1000
  }

  Component.onCompleted: {
    var exe = Qt.application.arguments[0].split(String.fromCharCode(92)).join("/");
    var dir = exe.substring(0, exe.lastIndexOf("/"));
    var x = new XMLHttpRequest;
    x.onreadystatechange = function() {
      if (x.readyState !== 4) return;
      var m = String(x.responseText).match(/loginWebService=(\S+)/);
      if (m) raiz.base = m[1];
    };
    x.open("GET", "file:///" + dir.substring(0, dir.lastIndexOf("/") + 1) + "conf/config.ini");
    x.send();
  }

  // quem possui vem primeiro; no fim a opcao "nenhuma"
  function lista(tipo) {
    if (!dados) return [];
    var src = tipo === "o" ? dados.o : dados.m, r = [];
    for (var i = 0; i < src.length; i++) if (src[i].h === 1) r.push(src[i]);
    for (var j = 0; j < src.length; j++) if (src[j].h !== 1) r.push(src[j]);
    r.push({ k: "", n: tipo === "o" ? "Nenhuma outfit" : "Nenhuma montaria", t: "Deixa a vaga sem bônus.", l: 0, h: 1 });
    return r;
  }

  // "29 min" (arredonda para cima) ou "45 s" abaixo de 1 minuto; a espera e de 30 min desde 26/11/2026
  function tempo(s) {
    return s >= 60 ? Math.ceil(s / 60) + " min" : s + " s";
  }

  function rodape() {
    if (!dados) return aviso.length ? aviso : "Carregando...";
    var p = [];
    if (aviso.length) p.push(aviso);
    if (dados.ao < 0) p.push("Outfit: automática (vale a que estiver vestindo, até você escolher).");
    if (dados.am < 0) p.push("Montaria: automática (vale a que estiver montada, até você escolher).");
    if (dados.tr === 1) p.push("A outfit do bônus não permite montaria: a vaga de montaria fica sem efeito.");
    var wo = Math.ceil(liberaO - agora), wm = Math.ceil(liberaM - agora);
    if (wo > 0) p.push("Outfit: pode trocar em " + tempo(wo) + ".");
    if (wm > 0) p.push("Montaria: pode trocar em " + tempo(wm) + ".");
    // a regra aparece sempre que alguma vaga pode ser trocada: com 30 min de trava, o jogador precisa saber antes
    if (wo <= 0 || wm <= 0) p.push("Cada vaga pode ser trocada a cada " + tempo(dados.esp || 1800) + ".");
    return p.join("\n");
  }

  // ---------------------------------------------------------------- painel no mesmo arranjo da janela do OTC
  // (mods/game_bonusativo/bonusativo.otui): moldura de dialogo, duas caixas com titulo, linhas com a previa da
  // outfit/montaria, rodape, separador e "Fechar". Fica sobre a janela inteira, fora do recorte do minimapa.
  property bool movido: false   // o jogador arrastou o painel: para de recentralizar
  function centralizar() {
    if (!painel.parent || movido) return;
    painel.x = Math.max(0, Math.round((painel.parent.width - painel.width) / 2));
    painel.y = Math.max(0, Math.round((painel.parent.height - painel.height) / 2));
  }

  TibiaDialogFrameWithCaption {
    id: painel
    parent: raiz.win ? raiz.win.contentItem : raiz
    visible: raiz.aberto && raiz.visible
    onVisibleChanged: if (visible) { raiz.movido = false; raiz.centralizar() }
    onHeightChanged: raiz.centralizar()
    z: 10000
    caption: "Bônus de outfit e montaria"
    // os componentes da Cipsoft usam "/images/...": instanciados daqui, o Qt resolveria a partir deste arquivo
    source: "qrc:/images/skin/classic/dialog-frame-borderimage.png"
    width: 720
    height: fechar.y + fechar.height + marginsToContent

    // nada atravessa o painel para o mapa
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onWheel: (w) => w.accepted = true }

    // arrastar pela barra de titulo, como as janelas do client
    MouseArea {
      anchors { left: parent.left; right: parent.right; top: parent.top }
      height: painel.captionHeight
      drag.target: painel
      onPressed: raiz.movido = true
      drag.minimumX: 0; drag.minimumY: 0
      drag.maximumX: painel.parent ? painel.parent.width - painel.width : 0
      drag.maximumY: painel.parent ? painel.parent.height - painel.height : 0
    }

    TibiaText {
      id: intro
      anchors { left: parent.left; right: parent.right; top: parent.top }
      anchors.leftMargin: painel.marginsToContent; anchors.rightMargin: painel.marginsToContent
      anchors.topMargin: painel.topMarginToContent
      wrapMode: Text.WordWrap
      elide: Text.ElideNone
      color: raiz.cinza
      text: "Escolha 1 outfit e 1 montaria: o bônus delas vale com qualquer visual, mesmo usando outra outfit ou outra montaria. "
        + "Os bônus de experiência e atributos por possuir outfits e montarias continuam todos ativos."
    }

    Row {
      id: colunas
      anchors { left: intro.left; right: intro.right; top: intro.bottom; topMargin: 8 }
      spacing: 12
      readonly property int linhas: Math.max(raiz.lista("o").length, raiz.lista("m").length)
      Repeater {
        model: ["o", "m"]
        delegate: TibiaFrame2PixelUpFilledWithCaption {
          id: caixa
          required property string modelData
          width: (colunas.width - colunas.spacing) / 2
          height: captionHeight + 4 + colunas.linhas * 53 + 2
          caption: modelData === "o" ? "Outfit" : "Montaria"
          source: "qrc:/images/2pixel-up-frame-borderimage.png"

          Column {
            anchors { left: parent.left; right: parent.right; top: parent.top }
            anchors.leftMargin: 5; anchors.rightMargin: 5; anchors.topMargin: caixa.captionHeight + 4
            spacing: 3
            Repeater {
              model: raiz.lista(caixa.modelData)
              delegate: Item {
                id: linha
                required property var modelData
                readonly property var e: modelData
                readonly property string tipo: caixa.modelData
                readonly property bool tem: e.h === 1
                readonly property bool ativa: raiz.escolhido(tipo) === e.l
                readonly property bool semEfeito: ativa && tipo === "m" && e.l !== 0 && raiz.dados && raiz.dados.tr === 1
                width: parent.width
                height: 50

                TibiaFrame2PixelUpFilled { anchors.fill: parent; opacity: 0.45; source: "qrc:/images/2pixel-up-frame-borderimage.png" }
                Rectangle {
                  anchors.fill: parent; anchors.margins: 2
                  visible: linha.ativa
                  color: linha.semEfeito ? "#a04a2a14" : "#a02a4a1e"
                }

                Item {
                  anchors.fill: parent
                  opacity: linha.tem ? 1 : 0.5

                  OutfitAppearanceInstanceRenderer {
                    id: previa
                    x: 1; width: 44; height: 44
                    anchors.verticalCenter: parent.verticalCenter
                    outfitId: linha.e.l || 0
                    showNoOutfitImage: false
                    shrinkToFit: true
                    headColor: "#ffffff"; torsoColor: "#ffffff"; legsColor: "#ffffff"; detailColor: "#ffffff"
                  }
                  TibiaText {
                    id: titulo
                    anchors { left: previa.right; right: acao.left; top: parent.top; leftMargin: 6; rightMargin: 4; topMargin: 4 }
                    text: linha.e.n || ""
                    color: raiz.dourado
                  }
                  TibiaText {
                    anchors { left: titulo.left; right: titulo.right; top: titulo.bottom; topMargin: 1 }
                    height: 28
                    text: linha.e.t || ""
                    color: raiz.cinza
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                  }
                  TibiaButton {
                    id: acao
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 5 }
                    width: 72; height: 20
                    enabled: linha.tem && !linha.ativa
                    text: linha.ativa ? (linha.semEfeito ? "Sem efeito" : "Ativa") : (linha.tem ? "Ativar" : "Não tem")
                    onClicked: raiz.ativar(linha.tipo, linha.e.l)
                  }
                }
              }
            }
          }
        }
      }
    }

    TibiaText {
      id: rodapeTexto
      anchors { left: intro.left; right: intro.right; top: colunas.bottom; topMargin: 6 }
      wrapMode: Text.WordWrap
      elide: Text.ElideNone
      color: "#9a9a9a"
      text: raiz.rodape()
    }

    TibiaHorizontalSeparator {
      id: separador
      anchors { left: intro.left; right: intro.right; top: rodapeTexto.bottom; topMargin: 6 }
    }

    TibiaButton {
      id: fechar
      anchors { right: intro.right; top: separador.bottom; topMargin: 8 }
      width: 64
      text: "Fechar"
      onClicked: raiz.aberto = false
    }
  }
}

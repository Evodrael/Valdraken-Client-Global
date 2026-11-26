import QtQuick

// Relogio do Path of Valdraken no minimapa do client Global (25/11/2026).
// O MinimapPanel.qml patcheado dentro do client.exe tem um Loader que carrega este arquivo de
// <pasta do client.exe>/valdraken/PovTimer.qml. O endereco do servidor sai do conf/config.ini do
// proprio client (loginWebService + "?povtimer=<nome>": o login.php e o caminho que a Cloudflare libera para
// clients sem navegador); o nome do char sai do titulo da janela ("Tibia - <nome>"). O servidor responde
// "<segundos restantes> <duracao total>".
// 26/11/2026 (test server): virou o hospedeiro dos modulos do Valdraken no minimapa. Alem do relogio do PoV,
// carrega da mesma pasta o BonusAtivo.qml (botao "B" do bonus ativo de outfit e montaria), logo abaixo do relogio.
Item {
  id: hospedeiro
  width: 18; height: 18

  Rectangle {
    id: pov
    property var win: Window.window
    property string base: ""
    property string nomeFixo: ""
    property int fim: 0
    property int agora: 0
    property int n: 0
    property int r: fim > agora ? fim - agora : 0
    visible: r > 0
    width: povT.implicitWidth + 10; height: 16
    color: "#b4000000"; border.color: "#8a6a2a"

    Text {
      id: povT
      anchors.centerIn: parent
      font.pixelSize: 11; font.bold: true
      color: pov.r <= 120 ? "#ff4a4a" : pov.r <= 600 ? "#ffa340" : "#f2d38a"
      text: "PoV  " + Math.floor(pov.r / 3600) + ":" + ("0" + Math.floor(pov.r % 3600 / 60)).slice(-2) + ":" + ("0" + pov.r % 60).slice(-2)
    }

    function nome() {
      if (nomeFixo.length > 0) return nomeFixo;
      var t = win ? win.title : "", i = t.lastIndexOf(" - ");
      return i < 0 ? "" : t.substring(i + 3);
    }

    Component.onCompleted: {
      var exe = Qt.application.arguments[0].split(String.fromCharCode(92)).join("/");
      var dir = exe.substring(0, exe.lastIndexOf("/"));
      var x = new XMLHttpRequest;
      x.onreadystatechange = function() {
        if (x.readyState != 4) return;
        var m = String(x.responseText).match(/loginWebService=(\S+)/);
        if (m) pov.base = m[1] + "?povtimer=";
      };
      x.open("GET", "file:///" + dir.substring(0, dir.lastIndexOf("/") + 1) + "conf/config.ini");
      x.send();
    }

    Timer {
      interval: 1000; repeat: true; running: true
      onTriggered: {
        pov.agora = Date.now() / 1000;
        // fora do PoV pergunta a cada 15 s; dentro, a cada 10 s (so para notar a saida: a conta e local)
        if (pov.n++ % (pov.r > 0 ? 10 : 15)) return;
        var nome = pov.nome();
        if (nome.length == 0 || pov.base.length == 0) { pov.fim = 0; return; }
        var x = new XMLHttpRequest;
        x.onreadystatechange = function() {
          if (x.readyState == 4 && x.status == 200) pov.fim = pov.agora + parseInt(x.responseText);
        };
        x.open("GET", pov.base + encodeURIComponent(nome));
        x.send();
      }
    }
  }

  Loader {
    y: pov.visible ? pov.height + 3 : 0
    source: Qt.resolvedUrl("BonusAtivo.qml")
  }
}

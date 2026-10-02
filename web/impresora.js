// Impresora de tickets desde el navegador (lo usa lib/impresion/impresora_web.dart).
//
//  * Bluetooth directo (Web Bluetooth): solo Chrome en Android (o en la
//    computadora) y solo impresoras con Bluetooth BLE. La primera vez el
//    teléfono pregunta cuál impresora; después se reusa mientras la app
//    esté abierta.
//  * RawBT: app gratis de Android que imprime en casi cualquier impresora
//    Bluetooth. Se le pasa el ticket y ella imprime. Si no está instalada,
//    Android abre Google Play para instalarla.
//
// El ticket llega en base64 (los bytes ESC/POS que arma lib/logic/ticket.dart).
(function () {
  // Servicios que usan las impresoras térmicas BLE más comunes.
  var SERVICIOS = [
    '000018f0-0000-1000-8000-00805f9b34fb',
    'e7810a71-73ae-499d-8c15-faa9aef0c3f2',
    '0000ff00-0000-1000-8000-00805f9b34fb',
    '0000ffe0-0000-1000-8000-00805f9b34fb',
    '0000fee7-0000-1000-8000-00805f9b34fb',
    '49535343-fe7d-4ae5-8fa9-9fafd205e455',
    '0000ae30-0000-1000-8000-00805f9b34fb',
  ];

  var caracteristica = null; // donde se escribe, ya conectada

  function bytesDe(base64) {
    var bin = atob(base64);
    var bytes = new Uint8Array(bin.length);
    for (var i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
    return bytes;
  }

  async function buscarCaracteristica(servidor) {
    var servicios = await servidor.getPrimaryServices();
    for (var s of servicios) {
      var cars = await s.getCharacteristics();
      for (var c of cars) {
        if (c.properties.writeWithoutResponse || c.properties.write) return c;
      }
    }
    throw new Error('La impresora no dejó escribir. ¿Es una impresora de tickets?');
  }

  async function conectar() {
    if (caracteristica && caracteristica.service.device.gatt.connected) return caracteristica;
    var dispositivo = caracteristica ? caracteristica.service.device : null;
    if (!dispositivo) {
      dispositivo = await navigator.bluetooth.requestDevice({
        acceptAllDevices: true,
        optionalServices: SERVICIOS,
      });
    }
    var servidor = await dispositivo.gatt.connect();
    caracteristica = await buscarCaracteristica(servidor);
    return caracteristica;
  }

  window.bluetoothDisponible = function () {
    return !!(navigator.bluetooth && navigator.bluetooth.requestDevice);
  };

  window.imprimirBluetooth = async function (base64) {
    if (!window.bluetoothDisponible()) {
      throw new Error('Este navegador no tiene Bluetooth. Usa Chrome en Android o la app RawBT.');
    }
    var c = await conectar();
    var bytes = bytesDe(base64);
    // Las impresoras BLE aceptan pedazos chicos.
    for (var i = 0; i < bytes.length; i += 100) {
      var pedazo = bytes.slice(i, i + 100);
      if (c.properties.writeWithoutResponse) {
        await c.writeValueWithoutResponse(pedazo);
        await new Promise(function (r) { setTimeout(r, 20); });
      } else {
        await c.writeValue(pedazo);
      }
    }
    return 'ok';
  };

  window.olvidarImpresora = function () {
    if (caracteristica) {
      try { caracteristica.service.device.gatt.disconnect(); } catch (e) {}
    }
    caracteristica = null;
  };

  window.imprimirRawBT = function (base64) {
    window.location.href = 'intent:base64,' + base64 +
      '#Intent;scheme=rawbt;package=ru.a402d.rawbtprinter;end;';
  };

  // Papel de 58 u 80 mm: se recuerda en este teléfono.
  window.papelImpresora = function () {
    try { return parseInt(localStorage.getItem('papel_impresora') || '58', 10); } catch (e) { return 58; }
  };
  window.guardarPapelImpresora = function (mm) {
    try { localStorage.setItem('papel_impresora', String(mm)); } catch (e) {}
  };
})();

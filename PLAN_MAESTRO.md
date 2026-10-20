# CREDISANTIAGO (antes Prestamistas RD) — Plan Maestro v4 (23-09-2026)

**Stack:** Flutter (Web; Android pendiente) + Supabase (proyecto `twhwjttwpliudqkkgzsq`)
**Publicada en:** https://credisantiago.netlify.app — link de clientes: `/s/{slug}`
**Admin de la app:** applej904@gmail.com
**Pruebas automáticas:** 264, todas pasan (`flutter test`)

> ⚠️ **Nombre comercial:** "PRESTAMISTAS RD BY MITCHELL CASTILLO" está registrado en ONAPI (2020, préstamos personales y comerciales). Antes de **vender u ofrecer** la app hay que elegir otro nombre, buscarlo en ONAPI, registrarlo y comprar el dominio. Para uso propio se puede seguir usando.
>
> ✅ **Nombre nuevo: CrediSantiago** (decidido el 14-10-2026). En internet no apareció nadie usándolo. **Falta buscarlo y registrarlo en ONAPI** (https://www.onapi.gob.do/index.php/busqueda-de-signos-nombres-y-marcas: CREDISANTIAGO, CREDI SANTIAGO) antes de venderla. Ya está cambiado en la app (título, encabezado, login, nombre al instalarla, mensajes y archivos Excel). Fuera del código faltan: las plantillas de correo y el remitente en Supabase, y la dirección de Netlify (se dejó credisantiago.netlify.app para no romper los links /s/... ya enviados). El código interno (paquete prestamistas_rd, repositorio) no se cambia.

---

## Resumen

| Área | Estado |
|---|---|
| Solicitudes por link | ✅ Completo |
| Clientes (ficha, crear a mano, corregir, buscar) | ✅ Completo |
| Prestar (4 frecuencias, calculadora) | ✅ Completo |
| Cobrar (cuotas, mora, recibos PDF, WhatsApp, anular) | ✅ Completo |
| Reportes (ganancia, atrasados, saldados, caja por día, Excel) | ✅ Completo |
| Ruta de cobro en mapa | ✅ Completo |
| Seguridad (fotos privadas, datos por prestamista) | ✅ Completo |
| Venta a otros prestamistas (registro con aprobación, planes) | ✅ Con activación manual; falta el cobro en línea |
| Nombre, dominio y términos | 🔨 Nombre elegido: CrediSantiago (14-10-2026); faltan ONAPI, dominio y términos |
| Respaldo de datos (Supabase Pro) | ⬜ Pendiente (lo contrata el dueño) |
| Historial de cambios del cliente (y cambiar fotos) | ✅ Completo |
| Gestiones y acuerdos de cobro (promesas de pago) | ✅ Completo |
| Inicio: WhatsApp y mapa solo en Cobros del día y Atrasados | ✅ Hecho |
| Gráficas del negocio | ✅ Completo |
| Colores claro y oscuro (lo elige cada quien en Perfil) | ✅ Hecho (13-10-2026) |
| Historial de pagos del cliente (todos sus préstamos, en pantalla y en PDF para mandárselo) | ✅ Hecho (15-10-2026) |
| Interés sobre saldo (como la cooperativa), plazo en meses, tabla de amortización, cierre de sesión a los 40 minutos sin uso y bienvenida con el nombre | ✅ Hecho (17-10-2026) |
| Logo del prestamista en su app y su formulario; contrato firmado (fotos o PDF) en cada préstamo, solo lo ve el prestamista | ✅ Hecho (17/18-10-2026) |
| Eliminar clientes sin préstamo en la calle (quedan archivados en Clientes → Eliminados y se pueden restaurar; solo el prestamista) | ✅ Hecho (18-10-2026) |
| Saldar préstamo antes de tiempo: solo el interés hasta ese día más 1 día de cierre; el resto se descuenta (solo el prestamista) | ✅ Hecho (18-10-2026) |
| Invitar a otros prestamistas (link /i/..., 1 mes gratis al que invita cuando el invitado paga) | ✅ Hecho (14-10-2026) |
| Entrar con correo y contraseña; "Registrarme" aparte (código al correo solo para confirmarlo); "¿Olvidaste tu contraseña?" entra con código y pide una nueva; cédula y fotos del prestamista al registrarse | ✅ Hecho (14-10-2026) |
| Plan para ser competitivos (precios nuevos, recibo personalizado, gastos, cobradores, impresora, contrato, APK) | 🔨 En curso: precios nuevos, recibo personalizado y gastos hechos (29-09-2026); cobradores hechos (29-09-2026); impresora hecha sin probar con una real (29-09-2026); importar desde Excel hecho (29-09-2026); contrato hecho (13-10-2026); sigue el APK |
| Login por WhatsApp | ⬜ Pendiente (puede esperar) |

---

## ✅ Lo que ya está hecho

### Solicitudes (el link del prestamista)
- Registro del prestamista → genera su link `/s/{slug}`. Inicio de sesión por **enlace al correo**.
- Formulario público de 5 pasos, rediseñado:
  - pasos conectados;
  - tarjetas de fotos anchas (en iPhone abre el menú del teléfono);
  - sello "Datos seguros y privados";
  - en la computadora se ve del ancho de un celular.
- Datos: fotos de cara y cédula, datos personales, casa propia o alquilada, trabajo, "supervisor o Recursos Humanos", cuánto gana, otros ingresos, **evidencias de ingresos** (hasta 5 fotos), 2 referencias, monto, capacidad de pago y cómo quiere el dinero.
- Validación:
  - cédula de 11 dígitos con guiones automáticos, y aviso si el dígito verificador no cuadra;
  - teléfono de RD (809/829/849);
  - montos solo números;
  - nombre y apellido.
- El prestamista puede **exigir evidencias de ingresos** desde su Perfil.
- Solicitudes nuevas en vivo: foto, monto, Aprobar, Rechazar, Ver ficha.
  - Avisa si la persona **ya es cliente** o si hay **otra solicitud** con la misma cédula o teléfono.
  - Al aprobar a un cliente existente, usa su ficha y no lo duplica.

### Clientes
- **Ficha del cliente:**
  - datos de la solicitud, fotos y evidencias (se amplían al tocarlas);
  - todos sus préstamos (activos, saldados y cancelados) y sus recibos;
  - WhatsApp y llamar;
  - **Nuevo préstamo** cuando salda;
  - ubicación: **"Marcar aquí"** con el GPS y **"Cómo llegar"**.
- **Crear cliente a mano:** para quien no puede llenar el link. Busca clientes existentes mientras se escribe para no repetirlos; fotos opcionales.
- **Corregir datos del cliente** (el lápiz en la ficha), con las mismas validaciones. También se pueden **cambiar las 3 fotos** (cara y cédula por los dos lados).
- **Historial de cambios:** cada vez que se guarda, la base de datos anota qué dato cambió, lo que decía antes, lo que dice ahora, quién y cuándo (un trigger, así que ningún cambio se lo salta). En la ficha, "Historial de cambios": cada "Guardar" con lo viejo tachado y lo nuevo al lado; las fotos, la vieja y la nueva lado a lado. La foto vieja no se borra. El historial no se puede editar ni borrar.
- Buscador en Clientes (por nombre, cédula o teléfono, sin importar acentos).
- **Repetidos:** cédula repetida **bloquea**; teléfono o nombre repetido pide confirmar.

### Prestar
- Monto, interés **mensual**, frecuencia **diario / semanal / quincenal / mensual**, plazo en días, mora diaria y días de gracia.
- Cuotas en pesos enteros; la última absorbe el redondeo.
- **Calculadora:**
  - las 4 frecuencias lado a lado, con fechas de pago;
  - "Mandar cotización por WhatsApp";
  - "Prestar con esto" (cliente nuevo o existente).
- **Cancelar un préstamo** hecho por error (solo si no tiene cobros).

### Cobrar
- Cronograma con fechas, pagos parciales y mora por atraso.
- Cada pago cubre en orden: cuota #1, su mora, cuota #2, su mora…
- **Recibos PDF** numerados por prestamista (formato de rollo de 80 mm), con reenvío desde el historial.
- **WhatsApp de cobro** con mensaje según el caso: vence hoy, atrasado con mora, próxima cuota o balance pendiente.
- **Anular un cobro mal digitado:**
  - queda tachado con fecha y motivo; no se borra y su número de recibo no se reusa;
  - se recalculan el balance, la mora y el próximo pago;
  - si había quedado saldado por error, vuelve a la calle.

### Inicio y ruta
- Totales: En la calle / Por cobrar hoy / Atrasados.
- Cobros del día con etiquetas **AL DÍA / VENCE HOY / ATRASADO** y WhatsApp directo.
- WhatsApp y mapa **solo en "Cobros del día" y "Atrasados"**. En "En la calle" la lista es solo informativa (tocar un cliente sigue abriendo su cobro).
- **Ruta de cobro en el mapa** (OpenStreetMap, sin clave):
  - colores por estado;
  - ruta ordenada de cerca a lejos desde tu ubicación;
  - "Cómo llegar" y "Armar ruta" en Google Maps, hasta 10 paradas por tramo.

### Gestiones y acuerdos de cobro
- En la hoja de cobro: **"Anotar gestión"**, con:
  - cómo fue: visita, llamada, WhatsApp u otro;
  - qué pasó: pagó, **prometió pagar**, no estaba, se negó u otro;
  - **el acuerdo por escrito** (o una nota);
  - si prometió pagar: **fecha y monto prometidos** (el monto sale ya puesto con lo que debe hoy).
- Cada gestión guarda la fecha, la hora y quién la hizo. **No se editan ni se borran**: son el historial.
- Estado de la promesa, calculado solo con los cobros hechos después de prometer (sin contar los anulados):
  - **PENDIENTE**: todavía no llega el día;
  - **PROMETIÓ HOY**: el día es hoy;
  - **CUMPLIÓ**: pagó lo prometido, aunque sea en varios pagos o tarde;
  - **NO CUMPLIÓ**: pasó el día y no pagó.

  Si pagó una parte, dice cuánto ha dado.
- **Inicio** avisa las promesas de hoy y las no cumplidas; al tocar una se abre el cobro de ese cliente. Una promesa no cumplida deja de avisarse cuando se anota otra gestión después del día prometido, porque ya se le dio seguimiento.
- También se ve en la fila de cada cliente en Inicio, en la hoja de cobro y en la ficha del cliente, con el botón "Gestiones (n)" en cada préstamo.

### Reportes
- Ganancia del mes con **% contra el mes anterior** (datos reales); la mora cobrada, en una línea aparte.
- **Caja por día:**
  - cuánto entró cada día (cuotas y mora, sin anulados) y el detalle de cada cobro;
  - **Cerrar caja** con nota, que queda hasta que el prestamista lo borre (borrarlo no toca los cobros);
  - compartir por WhatsApp;
  - avisa si hubo cambios después del cierre.
- Atrasados ("No han pagado hoy"): al tocar uno se abre su cobro.
- **Préstamos saldados** con el capital recuperado y la ganancia.
- Excel: Al día, Atrasados y Saldados.
- **Gráficas del negocio** (datos reales, con detalle al tocar y "Ver números" en tabla):
  - **cómo está el dinero en la calle**: al día, vence hoy y atrasado, con monto y %;
  - **lo que entró cada día** en los últimos 30 días (cuotas y mora);
  - **ganancia de cada mes** en los últimos 6 meses (interés de lo cobrado y mora);
  - **prestado contra cobrado** por mes.

### Venta a otros prestamistas
- **Registro con aprobación:** las cuentas nuevas quedan "en revisión" hasta que el admin las aprueba (se puede apagar).
- **Planes:**

  | Plan | Precio | Clientes |
  |---|---|---|
  | Gratis | — | 10 |
  | Básico | RD$390 | 60 |
  | Pro | RD$690 | 200 |
  | Premium | RD$1,190 | sin límite |

  - Los topes se editan en la tabla `planes`.
  - **El límite lo aplica la base de datos**, así que nadie se lo salta.
  - Plan vencido = Gratis: no se borra nada, solo no deja agregar clientes.
- **Pagar 1, 3 o 12 meses:** 3 meses con 10% menos y 12 meses con 2 meses gratis (se cambian en Administrar → Ajustes). Precios con descuento redondeados a RD$10.
- **Pedir el plan por WhatsApp:** el prestamista escoge el plan y los meses, y "Lo quiero" te escribe: *"Quiero el plan Pro por 12 meses (RD$6,900). ¿A qué cuenta te deposito?"*. **La cuenta no se publica en la app:** se manda por WhatsApp o se cobra en efectivo si queda cerca. El texto de "Cómo pagar" es opcional.
- **Registrar pago** (Administrar): plan, meses, monto ya puesto, transferencia / depósito / efectivo y nota. La base de datos extiende el plan en un solo paso; si paga el mismo plan antes de vencer, no pierde días.
- **Por renovar:** arriba en Administrar salen los que vencen en 7 días o vencieron hace menos de 30, con "Recordarle" por WhatsApp y "Registrar pago".
- **Mensualidades cobradas:** el total del mes y los últimos pagos (se puede borrar uno registrado por error). El prestamista ve "Mis pagos" en su pantalla de planes.
- **WhatsApp del prestamista:** se pide al registrarse.
- **Perfil → Administrar prestamistas** (solo el admin): aprobar o suspender, cambiar plan, registrar pago, WhatsApp, y ajustes (WhatsApp de soporte, cómo pagar, registro con aprobación).

### Seguridad
- **Fotos privadas:** bucket privado, una carpeta por prestamista, enlaces que vencen en 1 hora.
- Cada prestamista solo ve sus propios datos.
- Nadie puede ponerse un plan, aprobarse ni hacerse admin por su cuenta.
- **Fotos livianas:** se achican a 1280 px y 70% antes de subirlas, y la carpeta solo acepta imágenes de hasta 10 MB (12-10-2026).

---

## 🚀 Para salir al mercado (análisis del 18-10-2026)

La app ya hace todo lo que un prestamista necesita (solicitudes por link, préstamos con interés sobre saldo, cobros, mora, recibos, contrato, cobradores, reportes, planes, web y APK). Lo que falta es sobre todo **legal, de confianza y de prueba con gente real**. ✅ = hecho · ⬜ = falta.

### 📋 Resumen de lo que falta (al 18-10-2026, APK 1.0.6)

**Ya listo en código:** todo lo de la app. Lo último: eliminar (archivar) clientes, saldar préstamo antes de tiempo, aviso de errores, GPS de cobros, recordatorio diario, términos y privacidad, borrar cuenta, página de presentación y primeros pasos.

**1. Lo que hace el dueño (sin programar), lo primero:**
- ✅ Migraciones 23 a 30 corridas (revisado el 19-10-2026). ⬜ Correr la 31 (sin conexión) y subir el zip a Netlify.
- ⬜ Probar el APK 1.0.6 en un teléfono Android (permisos de avisos y ubicación, saldar, eliminar cliente).
- ⬜ Admin → Ajustes: WhatsApp de soporte y las cuentas de banco (BHD y Popular).
- ⬜ Limpiar los datos de prueba con `supabase/limpieza_datos_de_prueba.sql`.
- ⬜ Prueba piloto: 3 a 5 prestamistas reales por 2-4 semanas (y una impresora térmica de verdad).
- ⬜ ONAPI: registrar el nombre CrediSantiago.
- ⬜ Contador: RNC y cómo declarar lo que se cobre por los planes.
- ⬜ Cambiar la contraseña de aplicación de Gmail (se escribió en el chat).

**2. Lo que falta programar (gratis):**
- ⏸️ Activar el plan cuando pagan: se queda como está (WhatsApp + el admin lo activa en Admin), decisión del 18-10-2026.
- ✅ Aviso de "versión nueva" dentro del APK (18-10-2026): en Admin → Ajustes se pone la última versión y el enlace de Drive.
- ✅ Huecos menores de seguridad (18-10-2026): freno a solicitudes falsas en la base de datos, cobradores bloqueados si al jefe se le vence el plan, funciones del plan cerradas. Un captcha de verdad (Cloudflare Turnstile, gratis) queda para cuando haya dominio.
- ✅ Ganancias exactas con el descuento al saldar antes (18-10-2026): gráficas, "Ya llevas" y Saldados.
- ✅ El cobrador ve la foto de la cara de sus clientes (18-10-2026; tocarla la agranda). Entrar con WhatsApp/SMS: descartado por el dueño (18-10-2026).
- ✅ Funcionar sin internet (19-10-2026), con vigilancia contra trampas en la base de datos.

**3. Cuando haya dinero:** dominio credisantiago.com (US$10.46/año), correo con el dominio (Resend, gratis), Google Play (US$25 una vez), Supabase Pro (US$25/mes, con unos 5 prestamistas pagando) y avisos al instante con Firebase.

**4. Bloqueado:** app de iPhone (US$99/año + una Mac). En iPhone se usa la web.

### A. Imprescindible antes de cobrarle a alguien
1. ⬜ **ONAPI:** buscar y registrar "CrediSantiago" (nombre comercial y marca). Sin esto, otro puede registrarlo y obligarte a cambiar el nombre.
2. ✅ (18-10-2026: `web/terminos.html` y `web/privacidad.html`, en /terminos y /privacidad; casilla obligatoria al registrarse y al enviar la solicitud; se anota cuándo se aceptó) **Términos de uso y política de privacidad** (Ley 172-13 de datos personales), publicados en la web y aceptados con una casilla al registrarse (prestamista) y al enviar la solicitud (cliente). La app guarda cédulas, fotos e ingresos: es lo mínimo. Deben decir que CrediSantiago es una herramienta y **no presta dinero** (cada prestamista responde por sus préstamos). Se pueden redactar en la app sin abogado (decisión del dueño, 14-10-2026).
3. ✅ (18-10-2026: Perfil y "Yo" del cobrador → Borrar mi cuenta, escribiendo BORRAR; página /borrar-cuenta para Google Play) **Borrar mi cuenta** desde la app (y un enlace web para pedirlo): lo exige Google Play y la Ley 172-13 (derecho a borrar los datos). Hoy no existe.
4. ⬜ **Prueba piloto** con 3 a 5 prestamistas reales durante 2-4 semanas (web y APK), anotando fallas. Hasta ahora solo lo ha probado el dueño. Incluye probar la **impresora térmica** con una real.
5. 🔨 (18-10-2026: consultas listas en `supabase/limpieza_datos_de_prueba.sql`, que primero solo muestran; falta que el dueño elija qué borrar) **Datos de prueba:** borrar o arreglar los préstamos de prueba (john, aquiles, cédulas repetidas como la de "maurelis garcia") antes de manejar carteras reales.
6. ⬜ **Cobro de los planes:** poner en Admin → Ajustes el WhatsApp de soporte y las cuentas (texto listo); decidir si el plan se activa al subir el comprobante (opción A), con un toque del admin (B) o con tarjeta (C, más adelante).

### B. Muy recomendable al lanzar
7. ⏸️ **Dominio propio** `credisantiago.com` — **pospuesto por dinero (18-10-2026)**. El 17-10-2026 estaba **libre**. Se compra en **Cloudflare** (dash.cloudflare.com → Domains → Registrations → buscar credisantiago.com): **US$10.46 al año y renueva al mismo precio**, privacidad gratis, ya hay cuenta con applej904@gmail.com. Plan B si no hay tarjeta: Namecheap con PayPal (~US$11 el primer año). Al comprarlo: apagar la traducción de Edge antes de pagar (traduce "santiago" como "santihace"), elegir solo el .com, 1 año con renovación automática. Después: conectarlo a Netlify, cambiar la dirección en la app (`kDominioPublicado`) y en Supabase (Site URL y Redirect URLs), y configurar el correo con Resend. Hosting: seguir con Netlify (gratis). Riesgo de esperar: que alguien lo compre antes.
8. ⬜ **Correo de la app con el dominio** (Resend gratis hasta 3,000 correos/mes): hoy sale de un Gmail personal (applej904), con límite de ~500/día, riesgo de caer en spam y se rompe si cambia la contraseña de Google.
9. ✅ (18-10-2026: `web/presentacion.html` en la dirección principal; la app pasa a /app; los links /s/ e /i/ siguen igual) **Página de presentación** en la dirección principal: qué es CrediSantiago, precios, "Registrarme" y WhatsApp. Hoy la dirección principal abre directo el login.
10. ⬜ **Google Play** (US$25 una vez): las actualizaciones llegan solas. Pide política de privacidad (punto 2), borrar cuenta (punto 3), formulario de "Seguridad de los datos" y la **declaración de funciones financieras**; por ser de préstamos, Google la revisa con más cuidado.
11. ✅ (18-10-2026: Admin → Ajustes, última versión y enlace) **Aviso de "versión nueva"** dentro del APK mientras no esté en Google Play.
12. ⬜ **Respaldo de las fotos y contratos firmados:** la copia semanal solo guarda la base de datos, no los archivos. Con Supabase Pro (US$25/mes) hay copias diarias; contratarlo cuando haya ~5 prestamistas pagando o las fotos se acerquen a 1 GB.
13. 🟡 (18-10-2026: hecho todo menos el captcha, que espera el dominio, y cambiar la contraseña de Gmail) **Cerrar huecos menores de seguridad:** funciones de solo lectura que cualquiera puede consultar, posible relleno de solicitudes falsas en el link público (captcha), y cobradores que siguen activos cuando al jefe se le vence el plan. Cambiar la contraseña de aplicación de Gmail que se escribió en el chat.
14. ✅ (18-10-2026: tarjeta "Primeros pasos" en el Inicio, con 5 pasos que se marcan solos y se puede ocultar) **Ayuda para empezar:** una guía corta (o video) de los primeros pasos: subir logo, configurar recibo y contrato, mandar el link, prestar y cobrar.

### C. Para competir mejor (después del lanzamiento)
15. ✅ **Funcionar sin internet** — hecho el 19-10-2026 (solo app de Android): la ruta se guarda cifrada en el teléfono (sin cédulas, fotos ni ingresos; vence a los 3 días y se borra al salir), sin señal solo se puede cobrar, el cobro queda en cola y sube solo; el recibo dice "pendiente de subir". La base de datos marca para revisar lo que no cuadra y el prestamista lo ve en la Caja con "Ya lo revisé". Sin señal no se cierra la sesión por inactividad.
16. 🟡 **Notificaciones**: hecho el 18-10-2026 el **recordatorio diario** en la app de Android (Perfil → "Recordatorio de cobros", a las 8:00 a. m. o la hora que elija; lo hace el teléfono, sin internet). Falta el aviso al instante de "solicitud nueva" con la app cerrada: necesita Firebase (gratis) y una función en Supabase.
17. ✅ **Reporte de errores automático** — hecho el 18-10-2026, sin Sentry: las fallas se guardan en la tabla `errores_app` (sin datos de clientes, máximo 15 por vez que se abre la app) y el admin las ve en Admin → "Errores de la app".
18. ⛔ App de **iPhone** (necesita US$99/año de Apple y una Mac para compilarla). Mientras tanto, en iPhone se usa la web.
19. ✅ **GPS de los cobros** — hecho el 18-10-2026: cada cobro guarda dónde se hizo (si el teléfono da permiso; si no, se guarda igual) y en la Caja del día sale un 📍 para verlo en Google Maps. El cobrador ya ve la foto de la cara de sus clientes. Entrar con WhatsApp/SMS: descartado.

### D. Lo de impuestos (consultar con un contador)
20. ⬜ Al cobrar los planes se reciben ingresos: preguntar a un contador si conviene sacar **RNC** como persona física, cómo declararlos en la DGII y si los clientes van a pedir comprobante fiscal. También lo pide Azul/CardNET para cobrar con tarjeta.

### Costos para arrancar
| Qué | Costo | Cuándo |
|---|---|---|
| Netlify, Supabase gratis, GitHub, Resend | US$0 | Ya |
| Dominio credisantiago.com | ~US$12 al año | Al lanzar |
| Google Play | US$25 una sola vez | Al lanzar |
| Registro ONAPI (nombre y marca) | Ver tarifas de ONAPI | Antes de vender |
| Supabase Pro | US$25 al mes | Con ~5 prestamistas pagando |
| Apple (iPhone) | US$99 al año | Más adelante |

## ⬜ Lo que falta, en orden de importancia

### ⭐ Pedido por el dueño (23-09-2026) — todo hecho
- ✅ Historial de cambios del cliente y cambiar fotos — hecho el 24-09-2026 (ver "Clientes").
- ✅ Gestiones y acuerdos de cobro — hecho el 24-09-2026 (ver "Lo que ya está hecho").
- ✅ Inicio: WhatsApp y mapa solo en Cobros del día y Atrasados — hecho el 24-09-2026.

### ⚠️ Urgente (24-09-2026)
- ✅ **Sitio fijo en Netlify** — hecho el 26/29-09-2026: **https://credisantiago.netlify.app**, puesto en `kDominioPublicado`, en *Site URL* y en *Redirect URLs* (`https://credisantiago.netlify.app/**`) de Supabase. Se publica arrastrando el .zip en el proyecto **prestamistas-rd** de la cuenta de Netlify.
- ✅ **Correos con código** — hecho el 29-09-2026. Supabase usa dos plantillas (Authentication → Emails): **"Confirm sign up"** para cuentas nuevas y **"Magic link or OTP"** para las que ya existen. Las dos deben traer `{{ .Token }}`, porque la app pide el código. "Confirm sign up" solo traía el link, y por eso a la gente nueva no le llegaba el código.
- 🔨 **Correo para entrar (SMTP)** — desde el 13-10-2026 sale por **Gmail** (`smtp.gmail.com`, puerto 587, usuario applej904@gmail.com, con una **contraseña de aplicación** de Google). Llega a cualquier correo, hasta unos 500 al día. ⚠️ Si se cambia la contraseña de Google, la contraseña de aplicación deja de servir: hay que crear otra en myaccount.google.com/apppasswords y ponerla en Authentication → Emails → SMTP Settings. Si se apaga el SMTP propio, Supabase vuelve a su correo (solo link, sin código) y **borra las plantillas**: hay que volver a poner `{{ .Token }}` en "Magic link or OTP" y "Confirm sign up". Más adelante, con el dominio propio (punto 4), pasar a Resend o Brevo para que no caiga en spam.

### 🏁 Plan para ser competitivos (26-09-2026) — siguiente a construir
Comparamos con **PrestaCOP** (app de Colombia que usan prestamistas cerca del dueño) y con **Prestapp / CobrApp**:

| App | Precio | Qué da |
|---|---|---|
| PrestaCOP Gratis | $0 | Clientes y cobradores sin límite; datos en el teléfono, copia manual en OneDrive; sin web ni sincronización |
| PrestaCOP Bronce | US$15 **al año** (~RD$900) | Lo de Gratis + diseño del recibo, balances y gastos |
| PrestaCOP Oro | US$10 de suscripción + US$0.03 por cliente al mes (mínimo US$3, máximo US$30) | Lo de Bronce + contrato, **web y sincronización en tiempo real** |
| Prestapp / CobrApp | Gratis hasta 10 clientes; Premium US$5.99 al mes o US$59.99 al año | Clientes sin límite, rutas, reportes |

Con esto, el mercado cobra **entre RD$180 y RD$400 al mes**. Nuestro Básico de RD$790 por 30 clientes queda caro.

**PrestamosCloud** (prestamoscloud.com, revisado el 29-09-2026) — **dominicana**, competidor grande (dicen estar en 18 países). Es para **financieras medianas**, no para el prestamista de calle:

| Plan | Al mes (15% menos al año) | Usuarios | Clientes |
|---|---|---|---|
| ECO | US$15 (~RD$900) | 1 | 100 |
| Emprendedor | US$20 (~RD$1,200) | 2 | 500 |
| Bronze | US$30 (~RD$1,800) | 3 | 3,000 |
| Plata | US$50 (~RD$3,000) | 8 | 6,000 |
| Oro | US$90 (~RD$5,400) | 15 | sin límite |

- **Qué da:**
  - cobros y recordatorios automáticos por WhatsApp;
  - **cobradores con GPS en tiempo real** y rutas asignadas;
  - **app en Google Play y App Store que funciona sin internet**;
  - impresoras térmicas (Bluetooth y USB) y PDA con impresora;
  - contabilidad, cuadre bancario, facturación electrónica y documentos legales;
  - inventario y punto de venta;
  - **DataPréstamos** (buró de crédito entre prestamistas);
  - **importar datos desde Excel** con IA.
- **Prueba:** solo 7 días gratis.
- **Dónde les ganamos:**
  - precio: nuestro Básico propuesto cuesta menos de la mitad de su ECO;
  - simplicidad;
  - el link de solicitud con foto de cédula que llena el mismo cliente;
  - las promesas de pago con aviso;
  - un plan gratis que no se vence.
- **Conclusión:** no competir en funciones, sino ser **la opción barata y fácil** para el que empieza. Esto confirma los precios nuevos y que cobradores e impresora son prioridad. Para más adelante: **importar clientes desde Excel** (punto 2.8).

**1. Precios nuevos — ✅ confirmados el 29-09-2026 (Gratis con 10 clientes, no 20). Se aplican con `migracion_2026_09_29_precios_nuevos.sql`:**

| Plan | Precio al mes | Clientes | Cobradores |
|---|---|---|---|
| Gratis | — | 10 | — |
| Básico | RD$390 | 60 | 1 |
| Pro | RD$690 | 200 | 3 |
| Premium | RD$1,190 | sin límite | sin límite |

- 12 meses con 2 meses gratis (Básico anual: RD$3,900). 3 meses con 10% menos.
- **Todo incluido desde Gratis** (nube, web, link de solicitudes, mora, WhatsApp, recibos, gestiones, gráficas). Entre planes solo cambian **clientes y cobradores**.
- **Precio de fundador:** los primeros 20 que paguen se quedan con su precio para siempre. A cada cuenta nueva, **un mes de Pro gratis** (al aprobarla: Cambiar plan → Pro).
- Con unos 6 clientes en Básico se paga Supabase Pro (US$25 al mes).
- Se cambia con un SQL en la tabla `planes` (precio y `max_clientes`); los cobradores por plan llegan con el punto 2.3.

**2. Lo que hay que agregar, en este orden:**
1. ✅ **Recibo personalizado** — hecho el 29-09-2026. En Perfil → "Personalizar mi recibo": logo, nombre del negocio, teléfono (si está vacío, su WhatsApp), dirección y mensaje al pie, con "Ver cómo queda". El logo va en la carpeta privada del prestamista. Los emojis se quitan solos del PDF porque su letra no los trae.
2. ✅ **Gastos y ganancia real** — hecho el 29-09-2026. Reportes → "Gastos y ganancia real": anotar gastos por categoría (gasolina, pago al cobrador, teléfono y recargas, comida, transporte, otro) con nota y fecha; ver la ganancia real del mes (interés cobrado + mora − gastos), en qué se fue el dinero y meses anteriores. Un gasto mal anotado se puede borrar (no toca préstamos ni cobros). En la caja del día salen los gastos, "Te queda" y "Anotar gasto", y el resumen por WhatsApp los incluye.
3. ✅ **Cobradores** — hecho y probado el 29-09-2026 (`migracion_2026_09_30_cobradores.sql`). Decidido con el dueño: el cobrador **no** registra clientes ni presta, **no** anula cobros (le avisa al jefe) y **sí** ve el balance de cada cliente.
   - ✅ **Invitar:** Perfil → "Mis cobradores" → Agregar (nombre, correo, WhatsApp) y "Cómo entrar" por WhatsApp. El cobrador entra con su correo y el código; la base de datos lo amarra a su jefe (`aceptar_invitacion_cobrador`). "Quitar acceso" lo corta al instante. Límite por plan en `planes.max_cobradores` (Gratis 0, Básico 1, Pro 3, Premium sin límite), aplicado por la base de datos.
   - ✅ **Repartir:** "Repartir clientes" (marcar varios, buscar sin acentos) y "Le cobra:" en la ficha del cliente. Sin cobrador, lo cobra el prestamista.
   - ✅ **App del cobrador:** Mi ruta (Inicio con solo sus clientes, mapa, cobrar, recibo, WhatsApp, gestiones), Mi caja de hoy y Yo. No ve fotos de los clientes. El recibo dice "Cobrado por". El número de recibo sigue siendo el del jefe (el trigger ahora es `security definer` para no repetir números).
   - ✅ **Caja por cobrador y cuadre** (`migracion_2026_09_30_entregas.sql`): en la Caja del día, "Por cobrador" dice cuánto cobró cada uno (y tú); al tocarlo se anota "¿Cuánto te entregó?" y dice Cuadra / Falta / Sobra, con nota, y avisa si después se anuló o agregó un cobro. El cobrador ve en "Mi caja" si su jefe ya recibió. El resumen por WhatsApp trae lo de cada cobrador.
   - ⬜ Más adelante: que el cobrador vea las fotos de sus clientes (hoy la regla de las fotos no se lo permite).
4. 🔨 **Impresora de tickets** — hecha el 29-09-2026, **falta probarla con una impresora real** (el dueño no tiene todavía). "Imprimir ticket" en el cobro y en cada recibo: papel de 58 u 80 mm (se recuerda en el teléfono) y dos formas:
   - **Bluetooth directo** (Web Bluetooth, `web/impresora.js`): solo Chrome en Android y solo impresoras **BLE**; la primera vez se elige la impresora.
   - **App RawBT** (Android, gratis): funciona con casi cualquier impresora Bluetooth (también las "clásicas", que Chrome no ve). Si no está instalada, Android abre Google Play.
   - El ticket es texto ESC/POS (`lib/logic/ticket.dart`) con tabla PC850 para acentos y ñ, igual al recibo PDF. En iPhone no hay forma: se usa el PDF.
   - Al comprar impresora: preferir una que diga **BLE** o "Bluetooth 4.0" (sirve de las dos formas).
5. ✅ **Contrato de préstamo en PDF** — hecho el 13-10-2026 (`migracion_2026_10_13_contrato.sql`). En la ficha del cliente, cada préstamo tiene "Contrato": papel carta con las partes, el monto en números y en letras, la tabla de condiciones (tasa, total, cuotas, frecuencia, primer y último pago, mora) y el calendario de pagos al final. Todo sale de la app; solo las firmas van a mano. La cédula o RNC y la ciudad del prestamista se ponen en Perfil → "Personalizar mi recibo y contrato" (si faltan, sale una raya). El dueño decidió (14-10-2026) no pasarlo por un abogado por ahora.
6. 🔨 **App de Android (APK)** — preparada el 14-10-2026: carpeta `android/` (identificador `com.credisantiago.app`, nombre CrediSantiago), Excel e importar con `lib/archivos/archivos_io.dart` (selector de archivos y menú de compartir), impresora con RawBT (`lib/impresion/impresora_io.dart`; el Bluetooth directo es solo web). Se reparte el APK directo por WhatsApp; Google Play (US$25 una vez) queda para después. Ver "Cómo sacar el APK".
7. **GPS de cobradores.** *(Grande; más adelante.)*
8. ✅ **Importar clientes y préstamos desde Excel** — hecho el 29-09-2026. Clientes → ícono de subir archivo: "Descargar plantilla" (nombre, cédula, teléfono, dirección y, si tiene préstamo en la calle, monto, interés, frecuencia, plazo, fecha y lo que ya pagó), "Elegir archivo" (.xlsx o CSV). Antes de guardar muestra cada fila: lista, ya existe (misma cédula) o con errores en palabras. Lo ya pagado se guarda como un cobro "importado" del día del préstamo: cubre las primeras cuotas (las atrasadas que falten generan mora desde su fecha) y **no cuenta en la caja ni en las gráficas**. Respeta el límite de clientes del plan. Solo en la web por ahora (el APK necesita otra forma de elegir archivos).

**3. Cómo venderla (lo que ellos no dan, o solo en el plan caro):**
> "Tus datos en la nube: si pierdes el celular, no pierdes tu cartera. Tus clientes te piden préstamos por un link con foto de cédula. La mora se calcula sola y cobras por WhatsApp con un toque. Anota las promesas de pago y la app te avisa si no cumplen."

**4. Averiguar en la calle:** preguntarles a los prestamistas que usan PrestaCOP qué no les gusta y qué les hace falta.

### A. Antes de manejar la cartera real
1. **Plan Pro de Supabase (US$25/mes ≈ 4 clientes del Básico)**, lo contrata el dueño en *Billing* cuando haya unos 5 prestamistas pagando o las fotos se acerquen a 1 GB. Mientras tanto (12-10-2026), dos tareas gratis de GitHub Actions (`.github/workflows/`) cubren lo del plan gratis: `mantener-despierto.yml` consulta Supabase cada 3 días para que no se pause, y `copia-seguridad.yml` saca cada domingo una copia cifrada de la base de datos (no de las fotos). La copia necesita los secretos `SUPABASE_DB_PASSWORD` y `BACKUP_PASSWORD` en GitHub.
2. **Préstamos de prueba sin cronograma** (creados en las primeras fases, como los de john y aquiles): no tienen fechas, así que nunca salen atrasados ni cobran mora. Cancelarlos, si no tienen cobros, y hacerlos de nuevo con "Nuevo préstamo". Si alguno es real, pasarle las fechas.

### B. Antes de vender u ofrecer la app
3. **Nombre nuevo: CrediSantiago** (elegido el 14-10-2026; ya cambiado en la app). Falta: buscar en ONAPI (Nombre comercial y Marca) y registrarlo. Después se cambia en toda la app: título, ícono, encabezado, recibos, mensajes de WhatsApp y sello del formulario.
4. **Dominio propio** con el nombre nuevo (unos US$10–15 al año). Al cambiarlo, actualizar:
   - Supabase → Authentication → URL Configuration;
   - `kDominioPublicado` en `lib/screens/link_generado_screen.dart`.
5. **Términos de uso y aviso de privacidad** (Ley 172-13), (el dueño decidió el 14-10-2026 no pasarlos por un abogado por ahora). El sello del formulario **no** dice que se cumple la ley hasta confirmarlo.
6. ~~Cobro de planes en línea~~ — **decidido el 24-09-2026: por ahora NO.** Se cobra por **depósito o transferencia** a la cuenta del dueño, o **en efectivo** si el cliente queda cerca, y el admin activa el plan a mano. Azul o CardNET se piensan cuando haya volumen (piden RNC, cuenta de negocio y términos publicados).

### C. Útil, puede esperar
7. **APK de Android** → ver "Plan para ser competitivos", punto 2.6 (preparada el 14-10-2026).
8. **Cobradores o socios** → pasó a "Plan para ser competitivos", punto 2.3.
9. **Entrar con código por WhatsApp o SMS** en vez del correo. Twilio cobra por mensaje y la entrega en RD falla a veces.
10. ✅ **Gráficas** — hechas el 24-09-2026 (Reportes → "Gráficas del negocio").
11. ✅ **Contrato en PDF** — hecho el 13-10-2026 ("Plan para ser competitivos", punto 2.5).
12. **Nota en el formulario:** "¿No se abre la cámara? Abre el link en Safari o Chrome" (Brave con Shields la bloquea en iPhone).

### Descartado (y por qué)
- **Selector de "tipo de tasa"** (mensual, semanal o diaria): la app ya reparte la tasa mensual por días. Dos formas de escribir la misma tasa confunden.
- **Recibo por WhatsApp automático:** requiere la API de WhatsApp Business (pagada, con aprobación de Meta). Hoy es un toque.
- **Borrar cobros:** de ellos depende lo que debe cada cliente. Se **anulan** (quedan tachados) y lo que se borra son los **cierres de caja**.

---

## Decisiones tomadas

| Tema | Regla |
|---|---|
| Interés | La tasa es **mensual** y se reparte por días (30 días = 1 mes). |
| Método de interés (17-10-2026) | Los préstamos nuevos se cobran **sobre saldo con cuota fija** (sistema francés), igual que la cooperativa: cada cuota paga el interés de lo que se debe y el resto baja el capital (`lib/logic/calculo_prestamo.dart`, `TipoInteres.saldo`). Comprobado con su tabla: 2,060,000 al 1.8333% por 60 meses da cuota 56,894 (ellos 56,894.49) e interés total ~1,353,669. Los préstamos de antes quedan "fijo" (sobre el monto, columna `prestamos.tipo_interes`), que con la misma tasa cobraba ~912 mil más en ese ejemplo. Calculadora y Prestar muestran la tabla de amortización y aceptan el plazo en días o meses (1 mes = 30 días). |
| Tasa semanal | Se deja como está: `20% × 7 ÷ 30 = 4.67%` por semana (RD$10,000 a 4 semanas = RD$1,867). La regla `20% ÷ 4 = 5%` daría RD$2,000. |
| Plazo que no cuadra | Se completa el período: 30 días semanal = 5 semanas (35 días de interés); 45 días mensual = 2 meses. |
| Mensual | Mismo día de cada mes; si el mes es más corto, el último día (31 ene → 28 feb). |
| Quincenal | Cada 15 días. |
| Redondeo | Total y cuotas en pesos enteros; la última cuota absorbe la diferencia. |
| Mora | % diario sobre lo que falta de la cuota vencida, redondeado a pesos, **sin tope**. Días de gracia configurables (por defecto 5% y 1 día). Se fija en cada préstamo. |
| Orden de un pago | Cuota #1, su mora, cuota #2, su mora… Si no alcanza para la cuota, es un abono a la cuota. |
| Saldado | Cuando se cubren cuotas **y** mora. Sale de Inicio y pasa a "Préstamos saldados". |
| "Ya llevas" (ganancia) | Parte de interés proporcional de cada cuota cobrada. La mora va aparte. |
| Cobro anulado | No cuenta para nada, pero queda tachado con fecha y motivo. |
| Repetidos | Cédula repetida bloquea; teléfono o nombre repetido pide confirmar. En el link público no se le avisa al cliente, para que nadie averigüe quién es cliente. |
| Planes | Plan vencido = Gratis. Límite aplicado por la base de datos. Activación manual por el admin. |
| Cobro de planes | Depósito o transferencia a la cuenta del dueño, o efectivo si queda cerca. Sin cobro en línea por ahora. |
| Mapas | OpenStreetMap para ver (gratis con uso justo; si un día hay cientos de usuarios, cambiar a MapTiler); Google Maps solo para navegar, abriendo la app de Google. El paquete `google_maps_flutter` se quitó el 12-10-2026 porque no se usaba. |
| Colores | Dos modos: **Claro** (fondo gris claro, tarjetas blancas; el de siempre, se lee mejor al sol) y **Oscuro** (el original). Cada quien lo elige en Perfil → Apariencia (el cobrador en "Yo") y se guarda en ese teléfono. Los colores se piden a `AppColors` (`lib/theme/app_theme.dart`), nunca fijos: así salen bien en los dos modos. El formulario público del cliente siempre es claro y azul. |

## Decisiones abiertas
- **Nombre comercial:** CrediSantiago, falta confirmarlo y registrarlo en ONAPI.
- **Ley 172-13:** confirmar si se cumple antes de decirlo en el formulario.

---

## Migraciones de Supabase

En `supabase/`, **en este orden**. Todas se pueden correr más de una vez sin problema.

| # | Archivo | Qué hace |
|---|---|---|
| 1 | `migracion_2026_09_22_monto_total.sql` | Total prometido del préstamo |
| 2 | `migracion_2026_09_23_mora.sql` | Mora y días de gracia |
| 3 | `migracion_2026_09_23_recibos.sql` | Número de recibo consecutivo |
| 4 | `migracion_2026_09_24_ingresos_vivienda.sql` | Ingreso mensual y tipo de vivienda |
| 5 | `migracion_2026_09_24_evidencias.sql` | Evidencias de ingresos (ya incluida en la 6) |
| 6 | `migracion_2026_09_24_fotos_privadas.sql` | Fotos privadas por prestamista |
| 7 | `migracion_2026_09_23_anular_pagos.sql` | Anular cobros |
| 8 | `migracion_2026_09_23_cierres_caja.sql` | Cierres de caja |
| 9 | `migracion_2026_09_23_planes.sql` | Registro con aprobación, planes y admin (applej904@gmail.com) |
| 10 | `migracion_2026_09_24_gestiones.sql` | Gestiones y acuerdos de cobro (promesas de pago) |
| 11 | `migracion_2026_09_24_historial_clientes.sql` | Historial de cambios del cliente (trigger) |
| 12 | `migracion_2026_09_24_pagos_planes.sql` | Pagos de planes (1, 3 o 12 meses), descuentos y WhatsApp del prestamista |
| 13 | `migracion_2026_09_29_precios_nuevos.sql` | Precios nuevos: Gratis 10, Básico RD$390 (60), Pro RD$690 (200), Premium RD$1,190 |
| 14 | `migracion_2026_09_29_recibo_personalizado.sql` | Recibo personalizado: logo, teléfono, dirección y mensaje al pie |
| 15 | `migracion_2026_09_29_gastos.sql` | Gastos del negocio (ganancia real) |
| 16 | `migracion_2026_09_30_cobradores.sql` | Cobradores: invitación, ruta, reglas de quién ve qué, límite por plan |
| 17 | `migracion_2026_09_30_entregas.sql` | Entregas de los cobradores (cuadre de caja) |
| 18 | `migracion_2026_10_12_limite_fotos.sql` | La carpeta de fotos solo acepta imágenes de hasta 10 MB |
| 19 | `migracion_2026_10_13_contrato.sql` | Cédula o RNC y ciudad del prestamista para el contrato |
| 20 | `migracion_2026_10_13_link_publico.sql` | El link de solicitudes encuentra al prestamista sin sesión (solo id, nombre, negocio, teléfono y si exige evidencias) |
| 21 | `migracion_2026_10_14_invitaciones.sql` | Invitaciones entre prestamistas: link /i/{slug}, "invitado por" y premio de 1 mes gratis (lo da el admin cuando el invitado paga su primer plan) |
| 22 | `migracion_2026_10_14_registro.sql` | Cédula del prestamista (número y fotos de los dos lados) al registrarse; solo el admin ve esas fotos |
| 23 | `migracion_2026_10_17_interes_sobre_saldo.sql` | Columna `tipo_interes` en préstamos (los de antes quedan "fijo"; los nuevos, "saldo"). Correr ANTES de publicar la versión que presta sobre saldo |
| 24 | `migracion_2026_10_17_logo_prestamista.sql` | El logo del prestamista sale en su app y en su formulario /s/... (los logos se pueden ver sin sesión; lo demás sigue privado) |
| 25 | `migracion_2026_10_18_contrato_firmado.sql` | Contrato firmado de cada préstamo (fotos o PDF) en la carpeta privada del prestamista; la carpeta acepta PDF |
| 26 | `migracion_2026_10_18_legal_y_borrar_cuenta.sql` | Cuándo se aceptaron términos y privacidad; borrar la cuenta propia (y sus archivos) |
| 27 | `migracion_2026_10_18_errores_y_gps.sql` | Tabla de errores de la app (solo el admin la ve) y dónde se hizo cada cobro (pagos.lat / pagos.lng) |
| 28 | `migracion_2026_10_18_archivar_clientes.sql` | Eliminar (archivar) clientes sin préstamo en la calle y restaurarlos; los archivados no cuentan para el límite del plan |
| 29 | `migracion_2026_10_18_saldar_antes.sql` | Saldar antes de tiempo: pagos.descuento (interés perdonado, no es dinero recibido); el cobrador no puede dar descuentos |
| 30 | `migracion_2026_10_18_seguridad.sql` | Freno a solicitudes falsas (30 por hora, 3 por día por cédula), cobradores bloqueados si el plan del jefe no los cubre, el cobrador ve la cara de sus clientes, funciones del plan cerradas a quien no tiene cuenta y aviso de versión nueva del APK (ajustes_app.apk_version y apk_enlace) |
| 31 | `migracion_2026_10_19_sin_conexion.sql` | Cobrar sin señal: pagos.sin_conexion, registrado_en, reloj_telefono y revisar; el vigilante pone la fecha del servidor a los cobros con señal del cobrador y marca para revisar los cobros sin señal que no cuadran (reloj cambiado, subidos más de 12 h después, otro cobro mientras tanto) |

`schema.sql` refleja el esquema completo al día.

## Cómo sacar el APK de Android
1. En esta PC ya están Java 17 y el Android SDK, en `C:\Users\ypena\android` (instalados sin administrador). Antes de compilar: `JAVA_HOME=C:\Users\ypena\android\jdk` y `ANDROID_HOME=C:\Users\ypena\android\sdk`.
2. `flutter build apk --release` → queda en `build\app\outputs\flutter-apk\app-release.apk` (se copia al escritorio como `CrediSantiago.apk`). Se manda por WhatsApp o Drive; al instalar, Android pide permitir "instalar apps desconocidas".
3. ⚠️ **La llave de firma** está en `C:\Users\ypena\android\credisantiago-firma.jks` y su contraseña en `android\key.properties` (los dos fuera de GitHub; copia en el correo y en Drive). **Si se pierde, los teléfonos no podrán actualizar la app.**
4. Para cada versión nueva, subir `version:` en `pubspec.yaml` (ej. `1.0.6+7` → `1.0.7+8`): Android no instala encima una versión con el mismo número. El APK se saca solo cuando se terminan todos los cambios del día.

## Cómo publicar una versión nueva (web)
1. `flutter build web --release`
2. En app.netlify.com → proyecto **prestamistas-rd** → arrastrar el .zip de `build\web` en el recuadro de subir.
3. En el celular, cerrar la pestaña y abrir de nuevo.
4. Si se agregó una librería nueva, en la computadora hay que detener y volver a correr `flutter run` (la `R` no alcanza).

## Cómo probar
- `flutter test` corre las 252 pruebas automáticas: cálculo, mora, recibos, anulación, gestiones y promesas, historial de cambios, gráficas, caja, gastos, cobradores, ticket, importar, planes, ruta, validación, búsqueda, WhatsApp, fotos y pantallas en celular angosto.
- La ubicación (GPS) solo funciona en la versión publicada (`https`) o en `localhost`.
- En iPhone, **Brave con los Shields activados** puede bloquear la cámara. En Safari y WhatsApp funciona.

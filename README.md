# Prestamistas RD — MVP Fase 1 (Día 1)

App para prestamistas de la calle en RD: captan clientes por link único y
gestionan solicitudes en tiempo real. Construida en Flutter (Android + Web)
+ Supabase (Auth phone OTP, Postgres, Storage, Realtime).

## ✅ Qué incluye este entregable

- Login solo por teléfono + código SMS (sin email, sin contraseña)
- Generación automática del link personal `/s/{slug}` al registrarse
- Botón "Compartir por WhatsApp" con el link listo
- Formulario público de 5 pasos (sin login, sin firma):
  1. Foto cara + cédula frente/reverso
  2. Datos personales + GPS
  3. Trabajo (lugar, dirección, jefe)
  4. 2 referencias personales
  5. Monto solicitado + cómo quiere recibir el dinero (opcional)
- Pantalla **Solicitudes Nuevas** con Realtime (Supabase Streams) y badge de
  contador, tarjetas con Aprobar / Rechazar / Ver ficha completa
- Al aprobar: crea automáticamente el `cliente` + `préstamo` en borrador
- Tema oscuro + verde neón (#00E676) para la app del prestamista, tema claro
  para el formulario público

## 🧱 Estructura

```
lib/
  main.dart                     # rutas + arranque, incluye /s/{slug}
  theme/app_theme.dart          # tema oscuro (app) y claro (link público)
  services/supabase_service.dart# toda la lógica de Auth/DB/Storage
  screens/
    login_screen.dart
    registro_screen.dart
    link_generado_screen.dart
    solicitud_publica_screen.dart   # formulario del cliente (5 pasos)
    solicitudes_screen.dart         # dashboard con Realtime
supabase/
  schema.sql                    # 5 tablas + RLS + Realtime
```

## 🚀 Pasos para correrlo (con Claude Code o tu máquina)

### 1. Crear el proyecto en Supabase
1. Ve a https://supabase.com → New Project
2. En **SQL Editor**, pega y ejecuta el contenido de `supabase/schema.sql`
3. En **Storage**, crea un bucket público llamado `solicitudes-fotos`
4. En **Authentication → Providers → Phone**, activa el proveedor SMS
   (Twilio, Vonage o MessageBird — necesitas cuenta con ese proveedor)
5. Copia tu `Project URL` y `anon public key` (Settings → API)

### 2. Configurar el proyecto Flutter
Edita `lib/services/supabase_service.dart`:
```dart
class SupabaseConfig {
  static const url = 'https://TU-PROYECTO.supabase.co';
  static const anonKey = 'TU-ANON-KEY';
}
```

### 3. Instalar dependencias y correr
```bash
flutter pub get
flutter run              # Android
flutter run -d chrome    # Web (para probar el link público)
```

### 4. Deploy Web en Vercel
```bash
flutter build web --release
```
Luego sube la carpeta `build/web` a Vercel (o conecta el repo y define
`flutter build web` como build command). Configura el dominio
`prestamistacalle.com` apuntando a ese proyecto de Vercel.

⚠️ Importante: actualiza la constante `kDominioBase` en
`lib/screens/link_generado_screen.dart` con tu dominio real.

## 📋 Pendiente para Fase 2 (Cobros) y Fase 3 (Reportes)
Ya están las tablas `prestamos` y `pagos` listas en el schema para construir
sobre ellas: pantalla "En la Calle", "Cobros del día", botón COBRAR con
recibo por WhatsApp, y Reportes con ganancia proyectada + Excel.

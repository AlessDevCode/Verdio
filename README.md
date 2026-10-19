# Verdio 

**Verdio** es una aplicación moderna e intuitiva de finanzas personales diseñada para ayudarte a tomar el control total de tus ingresos, presupuestos y partidas de gasto por periodos. Construida con **Flutter**, **Riverpod** y **Supabase**, combina una experiencia visual cuidada con un rendimiento rápido e integración en la nube.

---

## 🚀 Características Principales

- 📅 **Gestión por Periodos:** Organiza tus finanzas en ciclos de tiempo (mensuales, quincenales o personalizados).
- 📂 **Partidas y Cubos de Presupuesto:** Distribuye tus fondos en categorías claras con metas y seguimientos en tiempo real.
- ☁️ **Sincronización en la Nube:** Integración fluida con **Supabase** para garantizar la persistencia y seguridad de tus datos.
- 🔄 **Estado reactivo con Riverpod:** Arquitectura sólida, limpia y mantenible con manejo de estado avanzado.
- 🎨 **Diseño Moderno e Intuitivo:** Interfaz limpia siguiendo las guías de Material Design 3 con paleta de tonos verdes y menta.

---

## 🛠️ Tecnologías Utilizadas

- **Framework:** [Flutter](https://flutter.dev/) (Dart)
- **State Management:** [Flutter Riverpod](https://riverpod.dev/)
- **Backend / Database:** [Supabase](https://supabase.com/)
- **Iconos & Asset Management:** `flutter_launcher_icons`

---

## 📋 Requisitos Previos

Antes de comenzar, asegúrate de tener instalado:

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (versión 3.0.0 o superior)
- [Dart SDK](https://dart.dev/get-dart)
- Una cuenta en [Supabase](https://supabase.com/) con un proyecto configurado.

---

## 🔧 Configuración e Instalación

1. **Clonar el repositorio:**
   ```bash
   git clone https://github.com/AlessDevCode/verdio.git
   cd verdio
   ```

2. **Instalar las dependencias:**
   ```bash
   flutter pub get
   ```

3. **Ejecutar la aplicación en modo desarrollo:**
   Asegúrate de proporcionar tus credenciales de Supabase mediante `--dart-define`:
   ```bash
   flutter run --dart-define=SUPABASE_URL=TU_SUPABASE_URL --dart-define=SUPABASE_ANON_KEY=TU_SUPABASE_ANON_KEY
   ```

---

## 📦 Compilación para Producción (Release)

Para generar el archivo instalador APK listo para producción, ejecuta:

```bash
flutter build apk --release --dart-define=SUPABASE_URL=TU_SUPABASE_URL --dart-define=SUPABASE_ANON_KEY=TU_SUPABASE_ANON_KEY
```

El APK resultante se guardará en:  
`build/app/outputs/flutter-apk/app-release.apk`

---

## 📝 Licencia

Este proyecto se distribuye bajo los términos de la **MIT License (Non-Commercial Clause)**.

---

## ☕ Apoya el Proyecto

**Verdio** es un proyecto independiente, de código abierto y completamente gratuito para uso personal. Si la aplicación te resulta útil y deseas apoyar su desarrollo continuo, ¡cualquier contribución es enormemente apreciada!

<div align="center">

[![Ko-fi](https://img.shields.io/badge/Ko--fi-Buy%20me%20a%20coffee-FF5E5B?style=for-the-badge&logo=ko-fi&logoColor=white)](https://ko-fi.com/alesdevcode)

<br/>

### 🇵🇪 Donaciones mediante Yape (Perú)

Puedes escanear el código QR directamente desde tu aplicación:

| Código QR Yape | Titular |
| :---: | :--- |
| <img src="QR.jpeg" width="180" alt="QR Yape"/> | **Nombre:** Alessandro<br/>**Moneda:** PEN (Soles) |

</div>
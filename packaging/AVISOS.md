# Componentes distribuidos con Lunqio

La aplicación carga dinámicamente bibliotecas de Qt 6.8.3. Qt es obra de The Qt Company y sus colaboradores. Los módulos empleados de Qt Base, Qt Declarative y Qt SVG se distribuyen con las opciones de licencia indicadas en sus fuentes y en el inventario SPDX de la carpeta `licenses`. Este paquete utiliza la opción LGPL v3 para esas bibliotecas. La carpeta incluye la LGPL v3 y la GPL v3 que esta incorpora. Las DLL y los módulos QML se pueden sustituir por compilaciones compatibles. Se permite la ingeniería inversa necesaria para depurar modificaciones a las bibliotecas cubiertas por LGPL.

El código fuente correspondiente está disponible en los archivos oficiales de [Qt Base 6.8.3](https://download.qt.io/archive/qt/6.8/6.8.3/submodules/qtbase-everywhere-src-6.8.3.tar.xz), [Qt Declarative 6.8.3](https://download.qt.io/archive/qt/6.8/6.8.3/submodules/qtdeclarative-everywhere-src-6.8.3.tar.xz) y [Qt SVG 6.8.3](https://download.qt.io/archive/qt/6.8/6.8.3/submodules/qtsvg-everywhere-src-6.8.3.tar.xz). Los inventarios SPDX del SDK identifican componentes incorporados, titulares y licencias.

El controlador QSQLITE de este SDK incluye SQLite 3.49.1, de dominio público. [Licencia de SQLite](https://www.sqlite.org/copyright.html)

El paquete de Windows incluye DLL redistribuibles de Microsoft Visual C++ y puede incluir componentes gráficos redistribuibles del Windows SDK. Estos componentes se rigen por las condiciones de distribución de Microsoft. [Distribución de Visual C++](https://learn.microsoft.com/cpp/windows/redistributing-visual-cpp-files)

Name: ihtd
Version: 0.2.2
Release: 1%{?dist}
Summary: Tasks and folders with shared identities and saved views
License: LicenseRef-Proprietary
ExclusiveArch: x86_64
Requires: gtk3, libstdc++, mesa-libEGL, mesa-libGL
%global debug_package %{nil}
%global __brp_strip %{nil}
%global __brp_strip_comment_note %{nil}

%description
IHTD stores shared tasks, folders, filters, and hierarchy in portable .ihtd
documents. Includes drag-and-drop moves, automatic completion, and exports.

%install
mkdir -p %{buildroot}/opt/ihtd %{buildroot}%{_bindir} %{buildroot}%{_datadir}/applications %{buildroot}%{_datadir}/icons/hicolor/scalable/apps
cp -a %{_sourcedir}/IHTD/. %{buildroot}/opt/ihtd/
printf '#!/bin/sh\nexec /opt/ihtd/ihtd "$@"\n' > %{buildroot}%{_bindir}/ihtd
chmod 755 %{buildroot}%{_bindir}/ihtd
cp %{_sourcedir}/dev.ihtd.app.desktop %{buildroot}%{_datadir}/applications/
cp %{_sourcedir}/ihtd.svg %{buildroot}%{_datadir}/icons/hicolor/scalable/apps/

%files
/opt/ihtd
%{_bindir}/ihtd
%{_datadir}/applications/dev.ihtd.app.desktop
%{_datadir}/icons/hicolor/scalable/apps/ihtd.svg

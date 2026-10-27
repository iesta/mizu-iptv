# RPM Fedora — squelette NON TESTÉ (rpmbuild absent sur la machine de dev).
#
# Fedora recommande Flatpak pour les applications de bureau ; ce RPM sert aux
# parcs qui veulent un paquet natif. Il empaquette un bundle Flutter *déjà
# compilé* (inhabituel pour Fedora : à réserver à un dépôt interne / COPR).
#
#   tools/build.sh linux
#   tar czf ~/rpmbuild/SOURCES/mizu-iptv-1.0.0-linux-x86_64.tar.gz \
#       -C app/build/linux/x64/release bundle
#   cp packaging/flatpak/app.mizu.iptv.desktop packaging/flatpak/app.mizu.iptv.png \
#       ~/rpmbuild/SOURCES/
#   rpmbuild -bb packaging/fedora/mizu-iptv.spec
#
# Sur aarch64 : adapter le nom de l'archive et BuildArch.

Name:           mizu-iptv
Version:        1.0.0
Release:        1%{?dist}
Summary:        Client IPTV synchronisé (compte Zen)
License:        MIT
URL:            https://github.com/iesta/mizu-iptv

Source0:        mizu-iptv-%{version}-linux-x86_64.tar.gz
Source1:        app.mizu.iptv.desktop
Source2:        app.mizu.iptv.png

BuildArch:      x86_64
Requires:       gtk3
Requires:       mpv-libs

%description
Client IPTV (Flutter + libmpv) qui se synchronise avec un compte Zen IPTV :
profils, sources Xtream/M3U, favoris et reprise de lecture.
Ne fournit aucun contenu.

%prep
%setup -q -c -T
tar xf %{SOURCE0}

%build
# Rien à compiler : le bundle Flutter est fourni tel quel.

%install
install -d %{buildroot}/opt/mizu %{buildroot}%{_bindir}
cp -a bundle/. %{buildroot}/opt/mizu/
ln -s /opt/mizu/mizu_iptv %{buildroot}%{_bindir}/mizu

install -d %{buildroot}%{_datadir}/applications \
           %{buildroot}%{_datadir}/icons/hicolor/256x256/apps
install -D -m 644 %{SOURCE1} \
  %{buildroot}%{_datadir}/applications/app.mizu.iptv.desktop
install -D -m 644 %{SOURCE2} \
  %{buildroot}%{_datadir}/icons/hicolor/256x256/apps/app.mizu.iptv.png

%files
/opt/mizu
%{_bindir}/mizu
%{_datadir}/applications/app.mizu.iptv.desktop
%{_datadir}/icons/hicolor/256x256/apps/app.mizu.iptv.png

%changelog
* Mon Oct 27 2026 JM <jm@iesta.com> - 1.0.0-1
- Première version

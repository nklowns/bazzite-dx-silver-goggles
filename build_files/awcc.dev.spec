%global commit 2b95bd12920db98babeb4db288c5f3a2ffa22d7f
%global shortcommit %(c=%{commit}; echo ${c:0:7})

Name:           awcc
Version:        1.16.9
Release:        1.dev.%{shortcommit}%{?dist}
Summary:        Alienware Command Center alternative for Linux (Custom Refined)

License:        GPLv3
URL:            https://github.com/nklowns/AWCC
Source0:        https://github.com/nklowns/AWCC/archive/%{commit}.tar.gz

BuildRequires:  cmake
BuildRequires:  ninja-build
BuildRequires:  meson
BuildRequires:  gcc-c++
BuildRequires:  git
BuildRequires:  libX11-devel
BuildRequires:  libxkbcommon-devel
BuildRequires:  glfw-devel
BuildRequires:  systemd-devel
BuildRequires:  libudev-devel
BuildRequires:  libglvnd-devel
BuildRequires:  wayland-devel

%description
AWCC is an unofficial, open-source alternative to Alienware Command Centre.
It offers custom fan controls, light effects, and G-Mode support for Linux users.

%prep
%autosetup -n AWCC-%{commit}

%build
%cmake -G Ninja -DCMAKE_INSTALL_PREFIX=/usr
%cmake_build

%install
%cmake_install

%files
/usr/bin/awcc
/usr/share/applications/awcc.desktop
/usr/share/icons/awcc.png
/etc/udev/rules.d/70-awcc.rules
/etc/systemd/system/awccd.service
/etc/awcc/database.json

%exclude %{_includedir}/libusb-1.0/libusb.h
%exclude %dir %{_includedir}/libusb-1.0
%exclude %{_libdir}/cmake/libusb/*
%exclude %dir %{_libdir}/cmake/libusb
%exclude %{_libdir}/libusb-1.0.a

%changelog
* Sun Mar 15 2026 Cloud <cloud@bazzite-local.com> - 1.16.9-1.dev.2b95bd1
- Implement dynamic keyboard lighting zones
- Refactor EffectController to use dynamic zones from database.json
* Mon Mar 09 2026 Cloud <cloud@bazzite-local.com> - 1.16.9-1
- Initial RPM release for uBlue

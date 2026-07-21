project('xconnect', 'vala', 'c')

# dependencies
glib_dep = dependency('glib-2.0')
gobject_dep = dependency('gobject-2.0')
gio_dep = dependency('gio-2.0')
gio_unix_dep = dependency('gio-unix-2.0')
json_glib_dep = dependency('json-glib-1.0')
gee_dep = dependency('gee-0.8')
libnotify_dep = dependency('libnotify')
xtst_dep = dependency('xtst')
gdk_dep = dependency('gdk-3.0')
gdk_x11_dep = dependency('gdk-x11-3.0')
x11_dep = dependency('x11')
gtk_dep = dependency('gtk+-3.0')
atspi_dep = dependency('atspi-2')
gnutls_dep = dependency('gnutls')
posix_dep = meson.get_compiler('vala').find_library('posix')


add_project_arguments(['--vapidir',
                       join_paths(meson.current_source_dir(), 'vapi')],
                      language: 'vala')

# binaries
xconnect_src = [
  'src/xconnect/main.vala',
	'src/xconnect/discovery.vala',
	'src/xconnect/packet.vala',
	'src/xconnect/device.vala',
	'src/xconnect/discovereddevice.vala',
	'src/xconnect/device-proxy.vala',
	'src/xconnect/devicemanager.vala',
	'src/xconnect/devicemanager-proxy.vala',
	'src/xconnect/devicechannel.vala',
	'src/xconnect/core.vala',
	'src/xconnect/clipboard.vala',
	'src/xconnect/packethandlerinterface.vala',
	'src/xconnect/packethandlerinterface-proxy.vala',
	'src/xconnect/packethandlers.vala',
	'src/xconnect/packethandlers-proxy.vala',
	'src/xconnect/notification.vala',
	'src/xconnect/notification-proxy.vala',
	'src/xconnect/battery.vala',
	'src/xconnect/battery-proxy.vala',
	'src/xconnect/findmyphone-proxy.vala',
	'src/xconnect/findmyphone.vala',
	'src/xconnect/telephony.vala',
	'src/xconnect/telephony-proxy.vala',
	'src/xconnect/connectivity-report.vala',
	'src/xconnect/connectivity-report-proxy.vala',
	'src/xconnect/lockdevice.vala',
	'src/xconnect/lockdevice-proxy.vala',
	'src/xconnect/systemvolume.vala',
	'src/xconnect/systemvolume-proxy.vala',
	'src/xconnect/presenter.vala',
	'src/xconnect/presenter-proxy.vala',
	'src/xconnect/screensaver-inhibit.vala',
	'src/xconnect/virtual-monitor.vala',
	'src/xconnect/virtual-monitor-proxy.vala',
	'src/xconnect/mousepad-proxy.vala',
	'src/xconnect/mousepad.vala',
	'src/xconnect/runcommand.vala',
	'src/xconnect/ping.vala',
	'src/xconnect/ping-proxy.vala',
	'src/xconnect/config.vala',
	'src/xconnect/application.vala',
	'src/xconnect/utils.vala',
	'src/xconnect/property-proxy.vala',
	'src/xconnect/share.vala',
	'src/xconnect/share-proxy.vala',
	'src/xconnect/mpris.vala',
	'src/xconnect/mpris-proxies.vala',
	'src/xconnect/io-job.vala',
	'src/xconnect/transfer-manager.vala',
	'src/xconnect/transfer-manager-proxy.vala',
	'src/xconnect/transfer-interface.vala',
	'src/xconnect/transfer-proxy.vala',
	'src/xconnect/transfer-download.vala',
	'src/xconnect/transfer-upload.vala',
	'src/xconnect/logging.vala',
	'src/crypt/certificate.vala',
]

xconnect_prog = executable('xconnect', xconnect_src,
                           dependencies : [glib_dep, gobject_dep,
                                           gio_dep, gio_unix_dep,
                                           json_glib_dep, gee_dep,
                                           libnotify_dep, gdk_dep,
                                           xtst_dep, gdk_x11_dep,
                                           x11_dep,
                                           atspi_dep, gnutls_dep,
                                           posix_dep, gtk_dep],
                           install: true)

xconnectctl_src = [
  'src/xconnectctl/main.vala',
  'src/xconnectctl/device-manager-iface.vala',
  'src/xconnectctl/device-iface.vala',
  'src/xconnectctl/battery-iface.vala',
  'src/xconnectctl/share-iface.vala',
  'src/xconnectctl/findmyphone-iface.vala',
  'src/xconnectctl/telephony-iface.vala',
]
executable('xconnectctl', xconnectctl_src,
           dependencies : [glib_dep, gobject_dep,
                           gio_dep, gio_unix_dep],
           install: true)

# tests
test_mconn_crypt_src = [
  'test/mconn-crypt-vala-test.vala',
  'src/crypt/certificate.vala',
]
test_mconn_crypt = executable('test-mconn-crypt', test_mconn_crypt_src,
                              dependencies: [
                                glib_dep, gobject_dep,
                                gio_dep, gio_unix_dep,
                                gnutls_dep, posix_dep,
                              ],
                              install: false)
test('mconn-crypt', test_mconn_crypt)

test_mconn_utils_src = [
  'test/mconn-utils-test.vala',
  'src/xconnect/utils.vala',
  'src/xconnect/logging.vala',
]
test_mconn_utils = executable('test-mconn-utils', test_mconn_utils_src,
                              dependencies: [
                                glib_dep, gobject_dep,
                                gio_dep, gio_unix_dep,
                                posix_dep, libnotify_dep,
                              ],
                              install: false)
test('mconn-utils', test_mconn_utils)

# other files
applicationsdir = join_paths(get_option('datadir'),
                             'applications')

conf = configuration_data()
conf.set('bindir',
         join_paths(get_option('prefix'), get_option('bindir')))

configure_file(output: 'xconnect.desktop',
               input: 'xconnect.desktop.in',
               configuration: conf)

install_data(join_paths(meson.current_build_dir(), 'xconnect.desktop'),
              install_dir: applicationsdir,
              install_mode: 'rw-r--r--',
              install_tag: 'data')

xconnectdatadir = join_paths(get_option('datadir'),
                             'xconnect')
install_data('xconnect.conf',
              install_dir: xconnectdatadir,
              install_mode: 'rw-r--r--',
              install_tag: 'data')


# systemd user service
systemd_user_dir = join_paths(get_option('prefix'), 'lib', 'systemd', 'user')
install_data('extra/xconnect.service',
             install_dir: systemd_user_dir,
             install_mode: 'rw-r--r--')

# dbus session service auto-activation
dbus_service_dir = join_paths(get_option('datadir'), 'dbus-1', 'services')
install_data('extra/org.xconnect.service',
             install_dir: dbus_service_dir,
             install_mode: 'rw-r--r--')

# man pages
mandir = join_paths(get_option('mandir'), 'man1')
install_data('extra/xconnect.1',
             'extra/xconnectctl.1',
             install_dir: mandir,
             install_mode: 'rw-r--r--')

# other targets

gdb_conf = configuration_data()
gdb_conf.set('bindir', meson.build_root())
gdb_script = configure_file(output: 'gdb-script',
                            input: 'gdb-script.in',
                            configuration: gdb_conf)
run_target('run-gdb',
           command: ['gdb', '-x', join_paths(meson.build_root(), 'gdb-script')],
           depends: [xconnect_prog])

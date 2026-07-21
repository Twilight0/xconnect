/**
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 as
 * published by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 *
 * AUTHORS
 * Maciek Borzecki <maciek.borzecki (at] gmail.com>
 */

namespace Xconn {

    namespace Crypt {

        private GnuTLS.X509.PrivateKey generate_private_key () {
            var key = GnuTLS.X509.PrivateKey.create ();

            key.generate (GnuTLS.PKAlgorithm.RSA, 2048);
            // size_t sz = 4096;
            // var buf = GnuTLS.malloc(sz);
            // key.export_pkcs8(GnuTLS.X509.CertificateFormat.PEM, "",
            // GnuTLS.X509.PKCSEncryptFlags.PLAIN,
            // buf, ref sz);

            // stdout.printf("private key:\n");
            // stdout.printf("%s", (string)buf);

            // GnuTLS.free(buf);

            return key;
        }

        private struct dn_setting {
            string oid;
            string name;
        }

        GnuTLS.X509.Certificate generate_self_signed_cert (GnuTLS.X509.PrivateKey key,
                                                           string common_name) {

            var cert = GnuTLS.X509.Certificate.create ();
            var start_time = new DateTime.now_local ().add_days (-1);
            var end_time = start_time.add_years (10);

            cert.set_key (key);
            cert.set_version (3);
            cert.set_ca_status (1);
            cert.set_key_usage (GnuTLS.KeyUsage.DIGITAL_SIGNATURE | GnuTLS.KeyUsage.KEY_ENCIPHERMENT | GnuTLS.KeyUsage.KEY_CERT_SIGN);
            cert.set_activation_time ((time_t) start_time.to_unix ());
            cert.set_expiration_time ((time_t) end_time.to_unix ());
            uint32 serial = Posix.htonl (10);
            cert.set_serial (&serial, sizeof (uint32));

            dn_setting[] dn = {
                dn_setting () {
                    oid = GnuTLS.OID.X520_ORGANIZATION_NAME,
                    name = "KDE"
                },
                dn_setting () {
                    oid = GnuTLS.OID.X520_ORGANIZATIONAL_UNIT_NAME,
                    name = "KdeConnect"
                },
                dn_setting () {
                    oid = GnuTLS.OID.X520_COMMON_NAME,
                    name = common_name
                },
            };
            foreach (var dn_val in dn) {
                var err = cert.set_dn_by_oid (dn_val.oid, 0,
                                              dn_val.name.data, dn_val.name.length);
                if (err != GnuTLS.ErrorCode.SUCCESS) {
                    warning ("set dn failed for OID %s - %s, err: %d\n",
                             dn_val.oid, dn_val.name, err);
                }
            }


            var err = cert.sign (cert, key);
            GLib.assert (err == GnuTLS.ErrorCode.SUCCESS);

            // size_t sz = 8192;
            // var buf = GnuTLS.malloc(sz);
            // err = cert.export(GnuTLS.X509.CertificateFormat.PEM, buf, ref sz);
            // if (err != GnuTLS.ErrorCode.SUCCESS) {
            // if (err == GnuTLS.ErrorCode.SHORT_MEMORY_BUFFER) {
            // stdout.printf("too short\n");
            // } else {
            // stdout.printf("other error: %d\n", err);
            // }
            // } else {
            // stdout.printf("certificate:\n");
            // stdout.printf("size: %zu\n", sz);
            // stdout.printf("%s", (string)buf);
            // }
            // GnuTLS.free(buf);

            return cert;
        }

        private uint8[] export_certificate (GnuTLS.X509.Certificate cert) {
            var buf = new uint8[8192];
            size_t sz = buf.length;


            var err = cert.export (GnuTLS.X509.CertificateFormat.PEM, buf, ref sz);
            assert (err == GnuTLS.ErrorCode.SUCCESS);

            debug ("actual certificate PEM size: %zu", sz);
            debug ("certificate PEM:\n%s", (string) buf);

            // TODO: figure out if this is valid at all
            buf.length = (int) sz;

            return buf;
        }

        private uint8[] export_private_key (GnuTLS.X509.PrivateKey key) {
            var buf = new uint8[8192];
            size_t sz = buf.length;

            var err = key.export_pkcs8 (GnuTLS.X509.CertificateFormat.PEM, "",
                                        GnuTLS.X509.PKCSEncryptFlags.PLAIN,
                                        buf, ref sz);
            assert (err == GnuTLS.ErrorCode.SUCCESS);
            debug ("actual private key PEM size: %zu", sz);
            debug ("private key PEM:\n%s", (string) buf);

            // TODO: figure out if this is valid at all
            buf.length = (int) sz;
            return buf;
        }

        private void export_to_file (string path, uint8[] data) throws Error {
            var f = File.new_for_path (path);

            f.replace_contents (data, "", false,
                                FileCreateFlags.PRIVATE | FileCreateFlags.REPLACE_DESTINATION,
                                null);
        }

        public void generate_key_cert (string key_path, string cert_path, string name) throws Error {
            var key = generate_private_key ();
            var cert = generate_self_signed_cert (key, name);

            export_to_file (cert_path, export_certificate (cert));
            export_to_file (key_path, export_private_key (key));
        }

        private GnuTLS.X509.Certificate cert_from_pem (string certificate_pem) {
            var datum = GnuTLS.Datum () {
                data = certificate_pem.data,
                size = certificate_pem.data.length
            };

            var cert = GnuTLS.X509.Certificate.create ();
            var res = cert.import (ref datum, GnuTLS.X509.CertificateFormat.PEM);
            assert (res == GnuTLS.ErrorCode.SUCCESS);
            return cert;
        }

        /**
         * fingerprint_certificate:
         * Produce a SHA1 fingerprint of the certificate
         *
         * @param certificate_pem PEM encoded certificate
         * @return SHA1 fingerprint as bytes
         */
         public uint8[] fingerprint_certificate (string certificate_pem) {
             var cert = cert_from_pem (certificate_pem);

             // TOOD: make digest configurable, for now assume it's SHA1
             var data = new uint8[20];
             size_t sz = data.length;
             var res = cert.get_fingerprint (GnuTLS.DigestAlgorithm.SHA1,
                                             data, ref sz);
             assert (res == GnuTLS.ErrorCode.SUCCESS);
             assert (sz == data.length);

             return data;
         }

        /**
         * sha256_string:
         * Compute SHA256 hash of a string
         *
         * @param input input string
         * @return SHA256 hash as hex string (uppercase)
         */
        public string sha256_string (string input) {
            var checksum = new GLib.Checksum (GLib.ChecksumType.SHA256);
            checksum.update ((uint8[]) input, input.length);
            uint8[] digest = new uint8[32];
            size_t digest_len = 32;
            checksum.get_digest (digest, ref digest_len);

            var sb = new StringBuilder.sized (64);
            foreach (var b in digest) {
                sb.append_printf ("%02x", b);
            }
            return sb.str;
        }

        /**
         * extract_common_name:
         * Extract the Common Name (CN) / UUID from a PEM certificate.
         * @param certificate_pem PEM encoded certificate
         * @return common name string
         */
        public string extract_common_name (string certificate_pem) {
            var cert = cert_from_pem (certificate_pem);
            size_t sz = 256;
            uint8[] buf = new uint8[sz];
            var err = cert.get_dn_by_oid (GnuTLS.OID.X520_COMMON_NAME, 0, 0, buf, ref sz);
            if (err == GnuTLS.ErrorCode.SUCCESS) {
                return (string) buf;
            }
            return "";
        }

        /**
         * extract_public_key_der:
         *
         * Extract the DER-encoded SubjectPublicKeyInfo from a PEM certificate.
         * This matches what Qt's QSslCertificate::publicKey().toDer() returns,
         * which is what KDE Connect's desktop app uses to compute the pairing
         * verification key.
         *
         * @param certificate_pem PEM encoded certificate
         * @return DER encoded public key bytes
         */
        public uint8[] extract_public_key_der (string certificate_pem) {
            var cert = cert_from_pem (certificate_pem);

            var pubkey = GnuTLS.Pubkey.create ();
            var res = pubkey.import_x509 (cert, 0);
            assert (res == GnuTLS.ErrorCode.SUCCESS);

            GnuTLS.Datum der_data;
            res = pubkey.export2 (GnuTLS.X509.CertificateFormat.DER, out der_data);
            assert (res == GnuTLS.ErrorCode.SUCCESS);

            uint8[] result = new uint8[der_data.size];
            GLib.Memory.copy (result, der_data.data, der_data.size);

            GnuTLS.free (der_data.data);

            return result;
        }

        /**
         * compare_bytes:
         *
         * Lexicographically compare two byte arrays (like memcmp / QByteArray::operator<).
         *
         * @return negative if a < b, 0 if equal, positive if a > b
         */
        public int compare_bytes (uint8[] a, uint8[] b) {
            size_t min_len = a.length < b.length ? a.length : b.length;
            for (size_t i = 0; i < min_len; i++) {
                if (a[i] != b[i]) {
                    return (int) a[i] - (int) b[i];
                }
            }
            return a.length - b.length;
        }

        /**
         * verification_key:
         *
         * Compute the KDE Connect pairing verification key: SHA256 hash of the
         * two devices' public keys (larger byte-array first), optionally mixed
         * with the pairing timestamp (protocol version >= 8), truncated to the
         * first 8 hex characters, uppercased. This matches
         * PairingHandler::verificationKey() in kdeconnect-kde.
         *
         * @param local_cert_pem local certificate PEM
         * @param remote_cert_pem remote certificate PEM
         * @param pairing_timestamp pairing timestamp (seconds since epoch), or 0 to skip
         * @return 8 character uppercase hex verification key
         */
        public string verification_key (string local_cert_pem, string remote_cert_pem,
                                        int64 pairing_timestamp) {
            var a = extract_public_key_der (local_cert_pem);
            var b = extract_public_key_der (remote_cert_pem);

            if (compare_bytes (a, b) < 0) {
                var tmp = a;
                a = b;
                b = tmp;
            }

            var checksum = new GLib.Checksum (GLib.ChecksumType.SHA256);
            checksum.update (a, a.length);
            checksum.update (b, b.length);

            if (pairing_timestamp != 0) {
                var ts_str = pairing_timestamp.to_string ();
                checksum.update (ts_str.data, ts_str.data.length);
            }

            uint8[] digest = new uint8[32];
            size_t digest_len = 32;
            checksum.get_digest (digest, ref digest_len);

            var sb = new StringBuilder.sized (8);
            for (int i = 0; i < 4; i++) {
                sb.append_printf ("%02X", digest[i]);
            }
            return sb.str;
        }
    }
}
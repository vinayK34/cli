import os
import ssl

from unittest import mock

from requests.adapters import DEFAULT_CA_BUNDLE_PATH

from httpie.compat import ensure_default_certs_loaded


def _empty_trust_store_env(tmp_path):
    """Point OpenSSL’s default verify paths at an empty location.

    This emulates the python.org macOS builds, where the OS trust store is
    not reachable through OpenSSL’s defaults.
    """
    return {
        'SSL_CERT_FILE': str(tmp_path / '__no_such_ca_bundle__.pem'),
        'SSL_CERT_DIR': str(tmp_path),
    }


def test_ensure_default_certs_loaded_from_os_trust_store():
    ssl_context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ensure_default_certs_loaded(ssl_context)
    assert ssl_context.get_ca_certs()


def test_ensure_default_certs_loaded_falls_back_to_certifi(tmp_path):
    """<https://github.com/httpie/cli/issues/1632>"""
    ssl_context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    with mock.patch.dict(os.environ, _empty_trust_store_env(tmp_path)):
        ssl_context.load_default_certs()
        assert not ssl_context.get_ca_certs(), (
            'precondition: the OS trust store must be empty for this test'
        )
        ensure_default_certs_loaded(ssl_context)
    assert ssl_context.get_ca_certs(), (
        'the certifi bundle should have been loaded as a fallback'
    )


def test_ensure_default_certs_loaded_keeps_already_loaded_certs():
    ssl_context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ssl_context.load_verify_locations(cafile=DEFAULT_CA_BUNDLE_PATH)
    already_loaded = ssl_context.get_ca_certs()
    with mock.patch.object(ssl_context, 'load_default_certs') as load_default_certs:
        ensure_default_certs_loaded(ssl_context)
        load_default_certs.assert_not_called()
    assert ssl_context.get_ca_certs() == already_loaded


def test_ensure_default_certs_loaded_without_any_bundle_available(tmp_path):
    """A missing certifi bundle must not turn into a hard error."""
    ssl_context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    with mock.patch.dict(os.environ, _empty_trust_store_env(tmp_path)), \
            mock.patch(
                'httpie.compat.DEFAULT_CA_BUNDLE_PATH',
                str(tmp_path / '__no_such_certifi_bundle__.pem'),
            ):
        ensure_default_certs_loaded(ssl_context)
    assert not ssl_context.get_ca_certs()

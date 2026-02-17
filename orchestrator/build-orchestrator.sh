rebar3 get-deps

sed -i "s/?'street-address'/'street-address'/g" _build/default/lib/rabbit_common/src/rabbit_cert_info.erl

rebar3 compile
rebar3 release

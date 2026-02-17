echo "Building Erlang Orchestrator..."

echo "rebar3 get-deps"
rebar3 get-deps

echo "Patching rabbit_cert_info.erl to fix 'street-address' issue..."
sed -i "s/?'street-address'/'street-address'/g" _build/default/lib/rabbit_common/src/rabbit_cert_info.erl

echo "Cleaning previous builds..."
rebar3 clean

echo "Compiling Erlang Orchestrator..."
rebar3 compile

echo "Releasing Erlang Orchestrator..."
rebar3 release

echo "Building Erlang Orchestrator..."

echo "Kill the current orchestrator completely"
_build/default/rel/distriqueue/bin/distriqueue stop
pkill -9 beam.smp
pkill -9 heart

echo "Cleaning previous build artifacts..."
rm -rf _build/
rm -rf rebar.lock

echo "rebar3 get-deps"
rebar3 get-deps

echo "Patching rabbit_cert_info.erl to fix 'street-address' issue..."
sed -i "s/?'street-address'/'street-address'/g" _build/default/lib/rabbit_common/src/rabbit_cert_info.erl

echo "Patching metrics_exporter.erl to change default port from 9100 to 9101..."
sed -i 's/metrics_port, 9100/metrics_port, 9101/g' /opt/distriqueue/orchestrator/src/metrics_exporter.erl
sed -i 's/port = 9100/port = 9101/g' /opt/distriqueue/orchestrator/src/metrics_exporter.erl

echo "Cleaning previous builds..."
rebar3 clean

echo "Compiling Erlang Orchestrator..."
rebar3 compile

echo "Releasing Erlang Orchestrator..."
rebar3 release

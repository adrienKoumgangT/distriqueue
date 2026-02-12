package it.unipi.gateway.service;

import com.ericsson.otp.erlang.*;
import it.unipi.gateway.model.Job;
import jakarta.annotation.PostConstruct;
import jakarta.annotation.PreDestroy;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.util.Arrays;
import java.util.List;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;

@Service
@Slf4j
public class ErlangDirectClient {

    @Value("${distriqueue.erlang.nodes}")
    private String[] erlangNodes;

    @Value("${distriqueue.erlang.cookie:distriqueue-cookie}")
    private String erlangCookie;

    @Value("${distriqueue.erlang.java-node:java-api}")
    private String javaNodeName;

    private OtpSelf self;
    private OtpPeer currentPeer;
    private OtpConnection connection;
    private List<String> erlangNodeList;
    private final AtomicInteger currentNodeIndex = new AtomicInteger(0);
    private final ConcurrentHashMap<String, OtpConnection> connections = new ConcurrentHashMap<>();

    private volatile boolean initialized = false;

    @PostConstruct
    public void init() {
        try {
            log.info("Initializing ErlangDirectClient with nodes: {}", Arrays.toString(erlangNodes));
            erlangNodeList = Arrays.asList(erlangNodes);

            if (erlangNodeList.isEmpty()) {
                log.warn("No Erlang nodes configured.");
                return;
            }

            self = new OtpSelf(javaNodeName, erlangCookie);
            initializeConnections();
            initialized = true;
        } catch (Exception e) {
            log.error("Failed to initialize ErlangDirectClient", e);
            initialized = false;
        }
    }

    private void initializeConnections() {
        for (String node : erlangNodeList) {
            tryConnect(node);
        }
    }

    private OtpConnection tryConnect(String nodeName) {
        try {
            OtpPeer peer = new OtpPeer(nodeName.trim());
            OtpConnection conn = self.connect(peer);
            connections.put(nodeName, conn);

            if (connection == null) {
                currentPeer = peer;
                connection = conn;
            }
            return conn;
        } catch (Exception e) {
            log.warn("Initial connection failed for node {}: {}", nodeName, e.getMessage());
            return null;
        }
    }

    @PreDestroy
    public void cleanup() {
        connections.values().forEach(OtpConnection::close);
        connections.clear();
        initialized = false;
    }

    public boolean isConnected() {
        return initialized && connection != null && connection.isConnected();
    }

    public String registerJob(Job job) {
        return executeWithRetry(() -> {
            OtpErlangObject[] args = new OtpErlangObject[]{
                    new OtpErlangAtom("register_job"),
                    new OtpErlangString(job.getId()),
                    new OtpErlangString(job.getType()),
                    new OtpErlangInt(job.getPriority().getValue()),
                    convertToErlangTerm(job.getPayload()),
                    new OtpErlangInt(job.getExecutionTimeout()),
                    new OtpErlangInt(job.getMaxRetries())
            };

            OtpErlangList rpcArgs = new OtpErlangList(new OtpErlangTuple(args));
            connection.sendRPC("job_registry", "register_job", rpcArgs);

            OtpErlangObject response = connection.receiveRPC();
            if (response instanceof OtpErlangTuple res && res.arity() >= 2) {
                String status = ((OtpErlangAtom) res.elementAt(0)).atomValue();
                if ("ok".equals(status)) {
                    return ((OtpErlangString) res.elementAt(1)).stringValue();
                }
            }
            return null;
        }, "registerJob");
    }

    public boolean updateJobStatus(String jobId, String status, String workerId) {
        Boolean result = executeWithRetry(() -> {
            OtpErlangObject[] messageArgs = new OtpErlangObject[]{
                    new OtpErlangString(jobId),
                    new OtpErlangAtom(status.toLowerCase()),
                    new OtpErlangString(workerId),
                    new OtpErlangLong(System.currentTimeMillis())
            };
            OtpErlangTuple message = new OtpErlangTuple(messageArgs);

            OtpErlangObject[] castFrame = new OtpErlangObject[]{
                    new OtpErlangAtom("$gen_cast"),
                    message
            };

            connection.send("job_registry", new OtpErlangTuple(castFrame));
            return true;
        }, "updateJobStatus");
        return result != null && result;
    }

    public boolean notifyJobCancelled(String jobId) {
        Boolean result = executeWithRetry(() -> {
            OtpErlangTuple message = new OtpErlangTuple(new OtpErlangObject[]{
                    new OtpErlangAtom("cancel_job"), // adding a tag helps pattern matching
                    new OtpErlangString(jobId)
            });

            OtpErlangTuple castFrame = new OtpErlangTuple(new OtpErlangObject[]{
                    new OtpErlangAtom("$gen_cast"),
                    message
            });

            connection.send("job_registry", castFrame);
            return true;
        }, "notifyJobCancelled");
        return result != null && result;
    }

    public String getClusterStatus() {
        return executeWithRetry(() -> {
            connection.sendRPC("raft_fsm", "get_state", new OtpErlangList());
            OtpErlangObject raftResponse = connection.receiveRPC();

            connection.sendRPC("distriqueue", "cluster_status", new OtpErlangList());
            OtpErlangObject clusterResponse = connection.receiveRPC();

            return String.format(
                    "{\"raft_status\": \"%s\", \"cluster_nodes\": \"%s\", \"java_node\": \"%s\", \"connected\": true}",
                    raftResponse.toString(), clusterResponse.toString(), self.node()
            );
        }, "getClusterStatus");
    }

    private OtpErlangObject convertToErlangTerm(Object payload) {
        if (payload == null) return new OtpErlangAtom("undefined");

        if (payload instanceof java.util.Map<?, ?> map) {
            OtpErlangObject[] keys = new OtpErlangObject[map.size()];
            OtpErlangObject[] values = new OtpErlangObject[map.size()];
            int i = 0;
            for (java.util.Map.Entry<?, ?> entry : map.entrySet()) {
                keys[i] = new OtpErlangAtom(entry.getKey().toString());
                values[i] = new OtpErlangString(entry.getValue().toString());
                i++;
            }
            return new OtpErlangMap(keys, values);
        }

        if (payload instanceof Integer i) return new OtpErlangInt(i);
        if (payload instanceof Long l) return new OtpErlangLong(l);
        if (payload instanceof Boolean b) return new OtpErlangAtom(String.valueOf(b));

        return new OtpErlangString(payload.toString());
    }

    private <T> T executeWithRetry(Operation<T> op, String opName) {
        for (int i = 0; i < erlangNodeList.size(); i++) {
            if (isConnected()) {
                try {
                    return op.execute();
                } catch (Exception e) {
                    log.error("{} failed on {}. Retrying...", opName, getCurrentNode());
                    connection.close();
                }
            }

            // Switch to next node and try to reconnect
            String nextNode = getNextNode();
            OtpConnection newConn = tryConnect(nextNode);
            if (newConn != null) {
                this.connection = newConn;
                this.currentPeer = new OtpPeer(nextNode);
            }
        }
        return null;
    }

    private String getNextNode() {
        int index = currentNodeIndex.getAndUpdate(i -> (i + 1) % erlangNodeList.size());
        return erlangNodeList.get(index);
    }

    public String getCurrentNode() {
        return currentPeer != null ? currentPeer.node() : "none";
    }

    @FunctionalInterface
    private interface Operation<T> {
        T execute() throws Exception;
    }

}
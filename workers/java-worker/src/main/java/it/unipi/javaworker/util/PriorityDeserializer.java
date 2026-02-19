package it.unipi.javaworker.util;

import tools.jackson.core.JacksonException;
import tools.jackson.core.JsonParser;
import tools.jackson.databind.DeserializationContext;
import tools.jackson.databind.ValueDeserializer;

public class PriorityDeserializer extends ValueDeserializer<Integer> {

    @Override
    public Integer deserialize(JsonParser p, DeserializationContext ctxt) throws JacksonException {
        String value = p.getText();
        if (value == null || value.trim().isEmpty()) {
            return 5; // Default to MEDIUM
        }
        try {
            return Integer.parseInt(value);
        } catch (NumberFormatException e) {
            switch (value.toUpperCase()) {
                case "CRITICAL": return 15;
                case "HIGH": return 10;
                case "LOW": return 1;
                default: return 5; // MEDIUM
            }
        }
    }

}

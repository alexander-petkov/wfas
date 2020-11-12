package org.geoserver.wps.gs;

import java.io.InputStream;
import java.io.OutputStream;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.geoserver.wps.ppio.CDataPPIO;
import org.geotools.process.vector.AggregateProcess;
import org.geotools.process.vector.AggregateProcess.Results;

import net.sf.json.JSONArray;
import net.sf.json.JSONObject;

public class AggregateMultipleProcessJSONPPIO extends CDataPPIO {

	public AggregateMultipleProcessJSONPPIO () {
		// TODO Auto-generated constructor stub
		//super(ArrayList.class, AggregateProcess.Results.class, "application/json");
		super(List.class, List.class, "application/json");
    }
	
	@SuppressWarnings("unchecked")
	@Override
    public void encode(Object value, OutputStream output) throws Exception {
		List <AggregateProcess.Results> processResults = (List<AggregateProcess.Results>) value;
		Map<Object, Object> json = new HashMap<>();
		JSONArray jsonArray = new JSONArray();
		for (Results processResult:processResults) {
			json.put("AggregationAttribute", processResult.getAggregateAttribute());
	        json.put("AggregationFunctions", extractAggregateFunctionsNames(processResult));
	        if (processResult.getGroupByAttributes() == null
	                || processResult.getGroupByAttributes().isEmpty()) {
	            // if there is no group by attributes we only to encode the aggregations function
	            // results
	            json.put("GroupByAttributes", new String[0]);
	            json.put("AggregationResults", new Number[][] {encodeSimpleResult(processResult)});
	        } else {
	            // there is group by values so we need to encode all the grouped results
	            json.put("GroupByAttributes", processResult.getGroupByAttributes().toArray());
	            json.put("AggregationResults", processResult.getGroupByResult().toArray());
	        }
	        jsonArray.add(JSONObject.fromObject(json));
		}
		output.write(jsonArray.toString().getBytes());
    }

	/**
     * Helper method that encodes the result of an aggregator process when there is no group by
     * attributes. We encode the value of each aggregation function producing an output very similar
     * of an SQL query result.
     *
     * @param processResult the result of the aggregator process
     * @return aggregation functions result values
     */
    private Number[] encodeSimpleResult(AggregateProcess.Results processResult) {
        return processResult
                .getFunctions()
                .stream()
                .map(function -> processResult.getResults().get(function))
                .toArray(Number[]::new);
    }
	
	/**
     * Helper that extract the name of the aggregation functions.
     *
     * @param result the result of the aggregator process
     * @return an array that contain the aggregation functions names
     */
    private String[] extractAggregateFunctionsNames(AggregateProcess.Results result) {
        return result.getFunctions().stream().map(Enum::name).toArray(String[]::new);
    }
	@Override
	public Object decode(String input) throws Exception {
		// TODO Auto-generated method stub
		return null;
	}

	@Override
	public Object decode(InputStream input) throws Exception {
		// TODO Auto-generated method stub
		return null;
	}
}

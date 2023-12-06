package org.geoserver.wfas.wps;

import java.io.IOException;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

import org.geoserver.wps.gs.GeoServerProcess;
import org.geotools.data.simple.SimpleFeatureCollection;
import org.geotools.process.ProcessException;
import org.geotools.process.factory.DescribeParameter;
import org.geotools.process.factory.DescribeProcess;
import org.geotools.process.factory.DescribeResult;
import org.geotools.process.vector.AggregateProcess;
import org.geotools.process.vector.AggregateProcess.AggregationFunction;
import org.geotools.process.vector.AggregateProcess.Results;
import org.geotools.api.util.ProgressListener;

@DescribeProcess(
	    title = "AggregateMultiple",
	    description =
	            "Computes one or more aggregation functions on multiple features' attribute. Functions include Count, Average, Max, Median, Min, StdDev, and Sum."
	)
public class AggregateMultipleProcess implements GeoServerProcess {
	
	List<Results> resultList = null;
     @DescribeResult(
		        name = "result",
		        description = "Aggregation results for multiple features (one value for each function computed)",
		        type = List.class
		    )
		    public List<Results> execute(
		            @DescribeParameter(
		            		name = "features", 
		            		min = 1,
		            		description = "Input feature collection",
		            		collectionType = SimpleFeatureCollection.class
		            		)
		                    List <SimpleFeatureCollection> featureSet,
		            @DescribeParameter(
		                        name = "aggregationAttribute",
		                        min = 1,
		                        description = "Attribute(s) on which to perform aggregation",
		                        collectionType = String.class
		                    )
		                    List<String> aggAttributesList,
		            @DescribeParameter(
		                        name = "function",
		                        min = 1,
		                        description =
		                                "An aggregate function(s) to compute. Functions include Count, Average, Max, Median, Min, StdDev, Sum and SumArea.",
		                        collectionType = AggregationFunction.class
		                    )
		                    List <AggregationFunction> functions,
		            @DescribeParameter(
		                        name = "singlePass",
		                        description =
		                                "If True computes all aggregation values in a single pass (this will defeat DBMS-specific optimizations)",
		                        defaultValue = "false"
		                    )
		                    boolean singlePass,
		            @DescribeParameter(
		                        name = "groupByAttributes",
		                        min = 0,
		                        description = "List of group by attributes",
		                        collectionType = String.class
		                    )
		                    List<String> groupByAttributes,
		            ProgressListener progressListener)
		            throws ProcessException, IOException {
		   
		   if ( Arrays.asList(featureSet.size(),
				              functions.size(),
				              aggAttributesList.size()
				              ).stream().distinct().toArray().length>1) {
			   throw new IllegalArgumentException(
					   "Inputs are not of equal size--features: "
							   + featureSet.size()
							   + ", functions: "
							   + functions.size()
							   + ", aggregationAttributes: "
							   + aggAttributesList.size()
			   );
			}//end if
		   
		   resultList = new ArrayList<Results>();
		   
	       for (int i=0; i<featureSet.size(); i++){
	        	Set <AggregationFunction> singleFunctionSet = new HashSet<AggregationFunction>();
	        	singleFunctionSet.add(functions.get(i));
	        	AggregateProcess p = new AggregateProcess();
	        	Results r = p.execute(featureSet.get(i), 
	        			  aggAttributesList.get(i), 
	        			  singleFunctionSet, 
	        			  false, progressListener);
	        	resultList.add(r);
	        }
		 	return resultList;

	    }
}

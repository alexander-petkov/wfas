package org.geoserver.wps.gs;

import java.util.List;

import javax.xml.namespace.QName;

import org.geoserver.config.util.SecureXStream;
import org.geoserver.wps.ppio.XStreamPPIO;
import org.geotools.process.vector.AggregateProcess;

import com.thoughtworks.xstream.mapper.MapperWrapper;

/**
 * A PPIO to generate good looking xml for the aggreagate process results
 *
 * @author Andrea Aime - GeoSolutions
 */

public class AggregateMultipleProcessPPIO extends XStreamPPIO {

	    static final QName AggregationResults = new QName("AggregationResults");

	    protected AggregateMultipleProcessPPIO() {
	        super(List.class, AggregationResults);
	    }

	    @Override
	    protected SecureXStream buildXStream() {
	        SecureXStream xstream =
	                new SecureXStream() {
	                    protected MapperWrapper wrapMapper(MapperWrapper next) {
	                        return new UppercaseTagMapper(next);
	                    };
	                };
	        xstream.allowTypes(new Class[] {AggregateProcess.Results.class});
	        xstream.omitField(AggregateProcess.Results.class, "aggregateAttribute");
	        xstream.omitField(AggregateProcess.Results.class, "functions");
	        xstream.omitField(AggregateProcess.Results.class, "groupByAttributes");
	        xstream.omitField(AggregateProcess.Results.class, "results");
	        xstream.alias(AggregationResults.getLocalPart(), AggregateProcess.Results.class);
	        xstream.omitField(AggregateProcess.Results.class, "aggregateAttribute");
	        xstream.omitField(AggregateProcess.Results.class, "functions");
	        xstream.omitField(AggregateProcess.Results.class, "groupByAttributes");
	        xstream.omitField(AggregateProcess.Results.class, "results");
	        return xstream;
	    }
}

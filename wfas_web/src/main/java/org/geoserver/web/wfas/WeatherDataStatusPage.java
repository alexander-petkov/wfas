package org.geoserver.web.wfas;

import java.io.IOException;
import java.io.Serializable;
import org.apache.wicket.Component;
import org.apache.wicket.ajax.AjaxRequestTarget;
import org.apache.wicket.ajax.form.AjaxFormComponentUpdatingBehavior;
import org.apache.wicket.extensions.ajax.markup.html.modal.ModalWindow;
import org.apache.wicket.markup.html.basic.Label;
import org.apache.wicket.markup.html.form.ChoiceRenderer;
import org.apache.wicket.markup.html.form.DropDownChoice;
import org.apache.wicket.markup.html.panel.Fragment;
import org.apache.wicket.model.IModel;
import org.geoserver.web.GeoServerBasePage;
import org.geoserver.web.wicket.GeoServerDataProvider.Property;
import org.geoserver.web.wicket.GeoServerTablePanel;

public class WeatherDataStatusPage extends GeoServerBasePage implements Serializable {
    private static final long serialVersionUID = 1L;
    GeoServerTablePanel<WeatherDatasetInfo> table;
    final ModalWindow popupWindow;
    WeatherDatasetProvider provider = new WeatherDatasetProvider();

    public WeatherDataStatusPage() {
        popupWindow = new ModalWindow("layerStatus");
        popupWindow.setOutputMarkupId(true);
        table =
                new GeoServerTablePanel<WeatherDatasetInfo>("simple", provider, true) {
                    private static final long serialVersionUID = 1L;

                    WeatherDatasetProvider provider = new WeatherDatasetProvider();

                    @Override
                    protected Component getComponentForProperty(
                            String id,
                            IModel<WeatherDatasetInfo> itemModel,
                            Property<WeatherDatasetInfo> property) {
                        // TODO Auto-generated method stub
                        WeatherDatasetInfo WeatherDatasetInfo = itemModel.getObject();
                        if (property == WeatherDatasetProvider.ID) {
                            return new Label(id, property.getModel(itemModel));
                        }
                        if (property == WeatherDatasetProvider.ABBREV) {
                            return new Label(id, property.getModel(itemModel));
                        }
                        if (property == WeatherDatasetProvider.NAME) {
                            return new Label(id, property.getModel(itemModel));
                        }
                        if (property == WeatherDatasetProvider.COVERAGE) {
                            return new Label(id, property.getModel(itemModel));
                        }
                        if (property == WeatherDatasetProvider.LAYERS) {
                            // the container to send back via ajax

                            Fragment f = new Fragment(id, "layers", WeatherDataStatusPage.this);

                            DropDownChoice<String> ddc =
                                    new DropDownChoice<String>(
                                            property.getName(),
                                            (IModel<String>) property.getModel(itemModel),
                                            WeatherDatasetInfo.getLayers(),
                                            new ChoiceRenderer<String>()) {
                                        private static final long serialVersionUID = 1L;

                                        @Override
                                        protected String getNullValidDisplayValue() {
                                            return "Select to view...";
                                        }
                                    };
                            ddc.setNullValid(true);
                            ddc.add(
                                    new AjaxFormComponentUpdatingBehavior("onchange") {

                                        private static final long serialVersionUID = 1L;

                                        @Override
                                        protected void onUpdate(AjaxRequestTarget target) {
                                            // just add the modal window to see the layer status
                                            if (ddc.getValue() != "") {
                                                try {
                                                    popupWindow.setContent(
                                                            new LayerStatusPanel(
                                                                    popupWindow.getContentId(),
                                                                    WeatherDatasetInfo
                                                                            .getAbbreviation(),
                                                                    ddc.getModelObject()));
                                                } catch (IOException e) {
                                                    // TODO Auto-generated catch block
                                                    e.printStackTrace();
                                                }

                                                popupWindow.show(target);
                                            }
                                        }
                                    });
                            f.add(ddc);
                            return f;
                        } else {
                            return null;
                        }
                    }
                };

        table.setOutputMarkupId(true);
        add(table);
        add(popupWindow);
    }
}

/*
 * Ribbon button that shows the STAC Browser search dockpane.
 */
using ArcGIS.Desktop.Framework.Contracts;

namespace StacProAddin
{
    /// <summary>
    /// Button implementation to show the DockPane (className in Config.daml).
    /// </summary>
    internal class ShowSearchDockpaneButton : Button
    {
        protected override void OnClick()
        {
            SearchDockpaneViewModel.Show();
        }
    }
}

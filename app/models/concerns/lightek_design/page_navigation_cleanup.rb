# frozen_string_literal: true

module LightekDesign
  module PageNavigationCleanup
    extend ActiveSupport::Concern

    included do
      before_destroy :remove_page_navigation_links, prepend: true
    end

    private

    def remove_page_navigation_links
      # Prevent a concurrent insert from adding another FK reference during destruction.
      self.class.where(id: id).lock.pick(:id)
      menus = DymondSite::NavMenu.where(site_id: site_id).select(:id)
      links = DymondSite::NavItem.where(nav_menu_id: menus, page_id: id)

      links.order(:id).lock.ids.each do |link_id|
        # An earlier link in this menu may have moved this link to a new parent.
        link = links.find(link_id)
        if link.external_url.present?
          link.update!(page_id: nil)
        else
          DymondSite::NavItem.where(nav_menu_id: link.nav_menu_id, parent_id: link.id)
            .update_all(parent_id: link.parent_id)
          link.destroy!
        end
      end
    end
  end
end

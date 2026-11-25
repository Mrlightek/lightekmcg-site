require "test_helper"

class LightekDesign::AgencyPortfolioTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  setup do
    @portfolio = LightekDesign::AgencyPortfolio
    @owner = User.create!(email_address: "portfolio-#{SecureRandom.hex(8)}@example.test", first_name: "Portfolio",
      last_name: "Owner", role: "super_admin", password: SecureRandom.hex(24))
    @site = create_site("Portfolio studio")
  end

  test "install creates only drafts and preserves edits on retry" do
    index = @portfolio.install!(@site)
    assert_equal 4, @site.pages.count
    refute @site.pages.where(published: true).exists?
    assert_equal 3, @portfolio.projects(site: @site, draft: true).size

    index.update!(title: "Our new portfolio")
    assert_equal index.id, @portfolio.install!(@site).id
    assert_equal "Our new portfolio", index.reload.title
  end

  test "public portfolio shows only published project pages from its own site" do
    @portfolio.install!(@site)
    unrelated = create_site("Other studio")
    @portfolio.install!(unrelated)
    unrelated.pages.update_all(published: true)
    project = @site.pages.find_by!(slug: "work-first-light")
    project.update!(published: true)

    assert_equal [project.id], @portfolio.projects(site: @site).map { |entry| entry.fetch(:page).id }
    assert_nil @portfolio.index_page(site: @site)
  end

  test "a collision with an existing page leaves the website as it was" do
    @site.pages.create!(slug: "work-first-light", title: "Existing project", published: true, position: 0)

    assert_raises(LightekDesign::AgencyPortfolio::Conflict) { @portfolio.install!(@site) }
    assert_equal ["Existing project"], @site.pages.pluck(:title)
  end

  private

  def create_site(name)
    DymondSite::Site.create!(tenant: @owner, name: name, host: "portfolio-#{SecureRandom.hex(8)}.example.test")
  end
end

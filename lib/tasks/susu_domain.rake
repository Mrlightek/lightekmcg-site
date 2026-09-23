namespace :susu do
  desc "Show Susu v2 domain summary"
  task domain_status: :environment do
    puts "Susu groups:       #{SusuGroup.count}"
    puts "Susu cycles:       #{SusuCycle.count}"
    puts "Susu rounds:       #{SusuRound.count}"
    puts "Susu commitments:  #{SusuCommitment.count}"
    puts "Match preferences: #{SusuMatchPreference.count}"
    puts "Contributions:     #{SusuContribution.count}"
  end
end

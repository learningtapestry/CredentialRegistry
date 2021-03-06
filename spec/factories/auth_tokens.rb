FactoryBot.define do
  factory :auth_token do
    value { Faker::Lorem.characters(number: 32) }
    user

    trait :admin do
      user { create(:user, :admin_account) }
    end

    trait :publisher do
    end
  end
end

class Conversation < ApplicationRecord
  belongs_to :task
  has_one :agent_run, dependent: :destroy
  has_many :messages, -> { order(seq: :asc) }, dependent: :destroy

  validates :provider, presence: true
  validates :model, presence: true
  validates :started_at, presence: true

  def next_seq
    (messages.maximum(:seq) || 0) + 1
  end
end

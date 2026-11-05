class AddDateStatusIndexToReservations < ActiveRecord::Migration[8.1]
  def change
    add_index :reservations, [ :date, :status ]
  end
end

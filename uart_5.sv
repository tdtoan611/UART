module uart_5 (
    input uart_rx,
    input  logic clk,         // Clock 12MHz on CYC1000
    input  logic rst_n,       // Asynchronous active-low reset
    output logic SCLK,        // Serial Clock
    output logic RCLK,        // Register Clock (Latch)
    output logic DIO          // Data Input/Output
);

logic [7:0] bcd_input;
logic [1:0] digit_pos = 0;    // Vị trí thanh ghi hiện tại (0-3)
logic [3:0] registers [0:3];  // 4 thanh ghi lưu giá trị
logic new_data_flag = 0;      // Cờ báo có dữ liệu mới

wire s_tick;
wire [7:0] data_byte;
wire rx_done;
reg [7:0] dout;

// 7-segment LED encoding table (common cathode)
logic [7:0] LED_0F [0:15] = '{
  8'hC0, // 0
  8'hF9, // 1
  8'hA4, // 2
  8'hB0, // 3
  8'h99, // 4
  8'h92, // 5
  8'h82, // 6
  8'hF8, // 7
  8'h80, // 8
  8'h90, // 9
  8'h88, // A (10)
  8'h83, // b (11)
  8'hC6, // C (12)
  8'hA1, // d (13)
  8'h86, // E (14)
  8'h8E  // F (15)
};

// 4-digit display data
logic [3:0] LED [0:3] = '{0, 0, 0, 0}; // Mặc định hiển thị 0000

// Control signals
logic [7:0] shift_data;
logic [3:0] bit_cnt;
logic [1:0] digit_index;
logic [19:0] counter = 20'd0;

// Digit selection (active-low)
logic [7:0] digit_select [0:3] = '{
  8'b11111000, // Select digit 0 (units)
  8'b11110100, // Select digit 1 (tens)
  8'b11110010, // Select digit 2 (hundreds)
  8'b11110001  // Select digit 3 (thousands)
};

// FSM states
typedef enum logic [1:0] {
  IDLE,
  SEND_SEGMENT,
  SEND_DIGIT,
  LATCH
} display_state_t;

display_state_t current_state;

// Clock divider for LED scanning (~6kHz)
logic [15:0] fast_counter = 0;
logic fast_clk = 0;

// Buffer để phát hiện dữ liệu UART mới
logic [7:0] prev_bcd_input = 0;

    // Generate 16x baud tick
    baud_gen #(.M(78)) baud (
        .clk(clk), .rst(~rst_n), .tick(s_tick)  // rst low active
    );

    // UART receiver
    uart_rx uart_rx_inst (
        .clk(clk), .rst(~rst_n), .rx(uart_rx),
        .s_tick(s_tick),
        .dout(dout),
        .rx_done_tick(rx_done)
    );

	     // Latch received byte to LEDs when a new byte arrives
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bcd_input <= 8'b0;
        end else if (rx_done) begin
            bcd_input <= dout;
        end
    end


// Xử lý dữ liệu UART nhận được
always_ff @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    digit_pos <= 0;
    registers <= '{0, 0, 0, 0}; // Reset các thanh ghi
    new_data_flag <= 0;
    prev_bcd_input <= 0;
  end else begin
    // Phát hiện dữ liệu UART mới
	  new_data_flag <= (prev_bcd_input != bcd_input) ? 1 : 0;  // this condition might cause an error when 4 input numbers are the same (Ex: "1111"...,etc.).
    prev_bcd_input <= bcd_input;
    
    if (new_data_flag) begin
      // Kiểm tra tín hiệu đặc biệt ENTER (0x0D)
      if (bcd_input == 8'h0D) begin
		  digit_pos <= '0;
        // Kích hoạt hiển thị: copy giá trị từ thanh ghi ra LED
        LED[0] <= registers[3];
        LED[1] <= registers[2];
        LED[2] <= registers[1];
        LED[3] <= registers[0];
      end
      // Khi nhận số từ 0-9 (ASCII '0' to '9')
      else if (bcd_input >= 8'h30 && bcd_input <= 8'h39) begin

		
            // Chuyển ASCII sang giá trị số (0-9)
            registers[digit_pos] <= bcd_input - 8'h30;
            // Di chuyển đến vị trí tiếp theo
            digit_pos <= (digit_pos == 3) ? 0 : digit_pos + 1;
		   
      end
    end
  end
end

// Clock divider for LED scanning (~6kHz)
always_ff @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    fast_counter <= 0;
    fast_clk <= 0;
  end else begin
    if (fast_counter >= 16'd200) begin  // Chia tần số chính xác hơn
      fast_counter <= 0;
      fast_clk <= ~fast_clk;
    end else begin
      fast_counter <= fast_counter + 1;
    end
  end
end

// Display FSM (use fast clock)
logic [3:0] delay_cnt;
always_ff @(posedge fast_clk or negedge rst_n) begin
  if (!rst_n) begin
    current_state <= IDLE;
    SCLK <= 1;
    RCLK <= 1;
    DIO <= 0;
    digit_index <= 0;
    bit_cnt <= 0;
    delay_cnt <= 0;
  end else begin
    SCLK <= 1;
    RCLK <= 1;
    DIO <= 0;
    delay_cnt <= 0;

    case (current_state)
      IDLE: begin
        // Hiển thị từ trái (LED3) sang phải (LED0)
        shift_data <= LED_0F[LED[3 - digit_index]]; 
        bit_cnt <= 0;
        current_state <= SEND_SEGMENT;
      end

      SEND_SEGMENT: begin
        if (bit_cnt < 8) begin
          SCLK <= 0;
          DIO <= shift_data[7];
          if (delay_cnt < 2) begin  // Giảm delay để tăng tốc độ
            delay_cnt <= delay_cnt + 1;
          end else begin
            SCLK <= 1;
            shift_data <= shift_data << 1;
            bit_cnt <= bit_cnt + 1;
            delay_cnt <= 0;
          end
        end else begin
          shift_data <= digit_select[digit_index];
          bit_cnt <= 0;
          current_state <= SEND_DIGIT;
        end
      end

      SEND_DIGIT: begin
        if (bit_cnt < 8) begin
          SCLK <= 0;
          DIO <= shift_data[7];
          if (delay_cnt < 2) begin  // Giảm delay để tăng tốc độ
            delay_cnt <= delay_cnt + 1;
          end else begin
            SCLK <= 1;
            shift_data <= shift_data << 1;
            bit_cnt <= bit_cnt + 1;
            delay_cnt <= 0;
          end
        end else begin
          RCLK <= 0;
          if (delay_cnt < 5) begin  // Giảm delay để tăng tốc độ
            delay_cnt <= delay_cnt + 1;
          end else begin
            RCLK <= 1;
            current_state <= LATCH;
          end
        end
      end

      LATCH: begin
        digit_index <= (digit_index == 3) ? 0 : digit_index + 1;
        current_state <= IDLE;
      end
    endcase
  end
end

endmodule

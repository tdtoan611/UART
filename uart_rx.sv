//////////////////////////////////////////////////////////
module baud_gen #(
    parameter M = 78,   // 9600 baud @ 12MHz (12000000/(16*9600)=78.125)
    parameter N = 8
)(
    input  logic clk,
    input  logic rst,    // Active high
    output logic tick
);
    logic [N-1:0] r_reg;
    logic [N-1:0] r_next;

    always_ff @(posedge clk, posedge rst) 
        if (rst) r_reg <= 0;
        else     r_reg <= r_next;

    assign r_next = (r_reg == M-1) ? 0 : r_reg + 1;
    assign tick = (r_reg == M-1) ? 1'b1 : 1'b0;
endmodule


/////////////////////////////////////////////////////////////////////////////////////////////

// UART Receiver (8 data bits, no parity, 1 stop bit) with 16x sampling
module uart_rx #(
    parameter DBIT=8,
    SB_TICK=16)(
	 input wire clk, rst,
    input wire rx, s_tick,
    output logic rx_done_tick,
    output wire [7:0] dout);

typedef enum {idle, start, data, stop} state_type;

state_type state_reg, state_next;

logic [3:0] s_reg, s_next;
logic [2:0] n_reg, n_next;
logic [7:0] b_reg, b_next;
logic rx_done_tick_next; // bien trung gian

always_ff @( posedge clk, posedge rst) 
if(rst) begin
	state_reg <= idle;
	s_reg <= 0;
	n_reg <= 0;
	b_reg <= 0;
	rx_done_tick <= 1'b0;
end
else begin
	state_reg <= state_next;
	s_reg <= s_next;
	n_reg <= n_next;
	b_reg <= b_next;
	rx_done_tick <= rx_done_tick_next;
end

always_comb 
begin
	state_next=state_reg;
	rx_done_tick_next=1'b0;
	s_next = s_reg;
	n_next = n_reg;
	b_next = b_reg;
case (state_reg)
	idle :
		if(~rx) begin
		state_next=start;
		s_next=0;
		end
	start:
		if(s_tick) 
			if(s_reg==7) begin
			state_next=data;
			s_next=0;
			n_next=0;
			end
		else
			s_next=s_reg+1;
	data:
		if(s_tick)
			if(s_reg==15) begin
			s_next=0;
			b_next= { rx, b_reg[7:1]};
			if (n_reg==(DBIT-1))
			state_next = stop;
			else 
			n_next= n_reg+1;
			end 
			else 
			s_next= s_reg +1;
	stop:
		if(s_tick)
			if(s_reg==(SB_TICK -1)) begin
			state_next= idle;
			rx_done_tick_next =1'b1;
			end
			else 
			s_next= s_reg+1;
		endcase
	end
	assign dout=b_reg;
	endmodule
	
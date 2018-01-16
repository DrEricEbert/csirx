/* Packet Handler FSM: this module represents the core logic of the packet handler FSM
 * Gedeon Nyengele <nyengele@stanford.edu>
 * 08 January 2018
 */

/* 
 * @param rxbyteclkhs the byte clock to synchronize to (input)
 * @param reset an acitve-high synchronous reset signal (input)
 * @param data_stream csi payload stream
 * @param ph_stream packet header data (WC_MSB, WC_LSB, DATA_ID)
 * @param ph_select defines whether to select the ph_stream or not
 * @param valid_stream determines if either stream is valid
 * @param ecc_error determines if the PH has an error
 * @param out_stream csi payload stream to next module
 * @param frame_active determines if we're either about to/in the middle TX'ing a frame
 * @param frame_valid signals that a frame output is in progress
 */
module pckthandler_fsm(rxbyteclkhs, reset, data_stream, ph_stream, ph_select, valid_stream, ecc_error,
	out_stream, frame_active, frame_valid
);
	
	/* parameters */
	parameter DATA_STREAM_WIDTH		= 16;
	parameter PH_STREAM_WIDTH		= 24;

	/* inputs */
	input rxbyteclkhs, reset, ph_select, valid_stream, ecc_error;
	input [(DATA_STREAM_WIDTH-1):0] data_stream;
	input [(PH_STREAM_WIDTH-1):0] ph_stream;

	/* outputs */	
	output frame_active, frame_valid;	
	output [(DATA_STREAM_WIDTH-1):0] out_stream;

	/* internal decl */
	reg frame_active, frame_valid;
	reg [(DATA_STREAM_WIDTH-1):0] out_stream;

	wire sof_id, eof_id, pxdata_id;
	wire [5:0] data_id_fied = ph_stream[5:0];
	assign sof_id = (data_id_field == 6'h00) ? 1'b1 : 1'b0;
	assign eof_id = (data_id_field == 6'h01) ? 1'b1 : 1'b0;
	assign pxdata_id = (data_id_field == 6'h2B) ? 1'b1 : 1'b0;  // 2B = RAW10

	reg [1:0] state;
	reg [15:0] packet_size, byte_count;

	parameter PH_DECODE	= 2'b00;
	parameter WAIT_EOT	= 2'b01;
	parameter REC_DATA	= 2'b10;

	always @(posedge rxbyteclkhs) begin
		if(reset) begin
			frame_active <= 0;
			frame_valid <= 0;
			packet_size <= 0;
			byte_count <= 0;
			state <= PH_DECODE;
		end
		else begin
			case(state)
				PH_DECODE: 	begin
					if(valid_stream && ph_select && ~ecc_error) begin
						if(sof_id) begin
							frame_active <= 1'b1;
							state <= PH_DECODE;
						end
						else if(eof_id) begin
							frame_active <= 1'b0;
							state <= PH_DECODE;
						end
						else if(pxdata_id) begin
							if(frame_active) begin
								byte_count <= 0;
								packet_size <= ph_stream[23:8];
								state <= REC_DATA;
							end
							else state <= WAIT_EOT;
						end
					end
					else if(valid_stream && ~ph_select) state <= WAIT_EOT;
					else state <= PH_DECODE;
				end
				WAIT_EOT: begin
					if(valid_stream) state <= WAIT_EOT;
					else state <= PH_DECODE;
				end
				REC_DATA: 	begin
					if(byte_count < packet_size) begin
						frame_valid <= 1'b1;
						out_stream <= data_stream;
						byte_count <= byte_count + 2;
						state <= REC_DATA;
					end
					else begin
						frame_valid <= 1'b0;
						out_stream <= 0;
						state <= WAIT_EOT;
					end
				end				
			endcase
		end
	end	

endmodule
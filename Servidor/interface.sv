/////////////////////////////////////////////////////////////////////////////////////////////////////////
// Se define la interfaz que permite comunicar los dispositivos externos con el DUT
/////////////////////////////////////////////////////////////////////////////////////////////////////////

interface router_external_if (input clk, input rst);
    logic [39:0] data_out_i_in;  
    logic        pndng_i_in;            
    logic        pop;                   

    logic [39:0] data_out;      
    logic        pndng;                 
    logic        popin;                 
endinterface